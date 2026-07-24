# frozen_string_literal: true

module Mammoth
  # Coordinates durable delivery progress across out-of-order workers.
  #
  # Work is registered in source order before dispatch. Completion may arrive
  # in any order, but a checkpoint and upstream acknowledgement advance only
  # when every item in the oldest closed source group has a durable outcome.
  # A source group is normally one PostgreSQL transaction.
  class DeliveryProgressCoordinator
    # Mutable source transaction tracked by the coordinator.
    class Group
      attr_reader :items
      attr_accessor :closed

      # @param items [Array<DeliveryProgressCoordinator::Entry>] registered work
      # @param closed [Boolean] whether the source group is complete
      def initialize(items:, closed:)
        @items = items
        @closed = closed
      end
    end

    # Mutable completion state for one registered work item.
    class Entry
      attr_reader :work, :source_position
      attr_accessor :completed

      # @param work [Object] registered work
      # @param source_position [String, Integer, nil] upstream position
      # @param completed [Boolean] whether a durable outcome was recorded
      def initialize(work:, source_position:, completed:)
        @work = work
        @source_position = source_position
        @completed = completed
      end
    end

    attr_reader :checkpoint_store, :source_name, :slot_name, :publication_name, :logger

    # @param checkpoint_store [Mammoth::CheckpointStore] durable checkpoint persistence
    # @param source_name [String] logical source name
    # @param slot_name [String] PostgreSQL replication slot name
    # @param publication_name [String] publication name
    # @param acknowledger [#call, nil] upstream durable-progress acknowledgement
    # @param position_resolver [#call, nil] source-owned durable position resolver
    def initialize(checkpoint_store:, source_name:, slot_name:, publication_name:, acknowledger: nil,
                   position_resolver: nil, logger: Logging::NullLogger::INSTANCE)
      @checkpoint_store = checkpoint_store
      @source_name = source_name
      @slot_name = slot_name
      @publication_name = publication_name
      @acknowledger = acknowledger
      @position_resolver = position_resolver
      @logger = logger
      # rubocop:disable Layout/LeadingCommentSpace -- Steep inline type syntax requires `#:`.
      @groups = [] #: Array[Group]
      @entries_by_work = {} #: Hash[untyped, Array[Entry]]
      # rubocop:enable Layout/LeadingCommentSpace
      @entries_by_work.compare_by_identity
      @mutex = Mutex.new
    end

    # Register work before dispatch.
    #
    # @param work [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope] work item
    # @param group_end [Boolean] whether this is the final item in its source group
    # @return [void]
    def register(work, group_end:)
      @mutex.synchronize do
        group = current_group
        entry = Entry.new(work: work, source_position: source_position(work), completed: false)
        group.items << entry
        (@entries_by_work[work] ||= []) << entry # steep:ignore
        group.closed = true if group_end
      end
      nil
    end

    # Mark a work item durably resolved and advance all newly contiguous groups.
    #
    # @param work [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope] work item
    # @return [String, nil] latest source position advanced by this call
    def complete(work)
      @mutex.synchronize do
        entry = pending_entry_for(work)
        raise ReplicationError, "delivery progress completed before registration" unless entry

        entry.completed = true
        advance_contiguous_groups
      end
    end

    # Close and advance a final source group after a clean end-of-stream.
    #
    # @return [String, nil] latest source position advanced by this call
    def finalize
      @mutex.synchronize do
        @groups.last.closed = true if @groups.last
        advance_contiguous_groups
      end
    end

    private

    def current_group
      return @groups.last if @groups.last && !@groups.last.closed

      Group.new(items: [], closed: false).tap { |group| @groups << group }
    end

    def pending_entry_for(work)
      @entries_by_work.fetch(work, []).find { |entry| !entry.completed } # steep:ignore
    end

    def advance_contiguous_groups
      advanced_position = nil

      while (group = @groups.first) && group.closed && group.items.all?(&:completed)
        position = group.items.reverse_each.lazy.map(&:source_position).find { |value| !value.nil? }
        persist_and_acknowledge(position) if position
        advanced_position = position || advanced_position
        remove_group(group)
      end

      advanced_position
    end

    def persist_and_acknowledge(position)
      checkpoint_store.write(
        source_name: source_name,
        slot_name: slot_name,
        publication_name: publication_name,
        last_lsn: position
      )
      @acknowledger&.call(position)
      logger.info("checkpoint_advanced", mammoth_name: source_name, slot: slot_name, publication: publication_name,
                                         source_position: position)
    end

    def remove_group(group)
      @groups.shift
      group.items.each do |entry|
        entries = @entries_by_work[entry.work]
        entries.delete(entry)
        @entries_by_work.delete(entry.work) if entries.empty?
      end
    end

    def source_position(work)
      return @position_resolver.call(work) if @position_resolver

      work.commit_lsn if work.respond_to?(:commit_lsn)
    end
  end
end
