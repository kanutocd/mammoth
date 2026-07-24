# frozen_string_literal: true

require "test_helper"
require "stringio"

module Mammoth
  # rubocop:disable Metrics/ClassLength
  class DeliveryProgressCoordinatorTest < Minitest::Test
    def test_does_not_advance_past_out_of_order_completion
      with_coordinator do |coordinator, checkpoint_store, acknowledgements|
        first = core_event(event_id: "event-1", source_position: "0/1")
        second = core_event(event_id: "event-2", source_position: "0/2")
        third = core_event(event_id: "event-3", source_position: "0/3")
        [first, second, third].each { |work| coordinator.register(work, group_end: true) }

        coordinator.complete(second)
        coordinator.complete(third)

        assert_equal 0, checkpoint_store.count
        assert_empty acknowledgements

        coordinator.complete(first)

        assert_equal "0/3", checkpoint(checkpoint_store).fetch("last_lsn")
        assert_equal %w[0/1 0/2 0/3], acknowledgements
      end
    end

    def test_serializes_completion_from_concurrent_workers
      with_coordinator do |coordinator, checkpoint_store, acknowledgements|
        first = core_event(event_id: "event-1", source_position: "0/1")
        second = core_event(event_id: "event-2", source_position: "0/2")
        coordinator.register(first, group_end: true)
        coordinator.register(second, group_end: true)
        second_completed = Queue.new

        later = Thread.new do
          coordinator.complete(second)
          second_completed << true
        end
        earlier = Thread.new do
          second_completed.pop
          coordinator.complete(first)
        end
        [later, earlier].each(&:join)

        assert_equal "0/2", checkpoint(checkpoint_store).fetch("last_lsn")
        assert_equal %w[0/1 0/2], acknowledgements
      end
    end

    def test_waits_for_every_event_in_a_transaction_group
      with_coordinator do |coordinator, checkpoint_store, acknowledgements|
        first = core_event(event_id: "event-1", source_position: "0/9")
        second = core_event(event_id: "event-2", source_position: "0/9")
        coordinator.register(first, group_end: false)
        coordinator.register(second, group_end: true)

        coordinator.complete(first)

        assert_equal 0, checkpoint_store.count
        assert_empty acknowledgements

        coordinator.complete(second)

        assert_equal "0/9", checkpoint(checkpoint_store).fetch("last_lsn")
        assert_equal ["0/9"], acknowledgements
      end
    end

    def test_persists_checkpoint_before_acknowledging_upstream
      with_temp_dir do |dir|
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        observed_checkpoint = nil
        coordinator = build_coordinator(checkpoint_store, acknowledger: lambda { |_position|
          observed_checkpoint = checkpoint(checkpoint_store)
        })
        work = core_event(source_position: "0/A")
        coordinator.register(work, group_end: true)

        coordinator.complete(work)

        assert_equal "0/A", observed_checkpoint.fetch("last_lsn")
      end
    end

    def test_logs_checkpoint_advancement
      with_temp_dir do |dir|
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        output = StringIO.new
        logger = Logging::Logger.new(level: "info", output:)
        coordinator = build_coordinator(checkpoint_store, acknowledger: nil, logger:)
        work = core_event(source_position: "0/A")
        coordinator.register(work, group_end: true)

        coordinator.complete(work)

        record = JSON.parse(output.string)
        assert_equal "checkpoint_advanced", record.fetch("event")
        assert_equal "0/A", record.fetch("source_position")
        assert_equal "mammoth_prod", record.fetch("slot")
      end
    end

    def test_uses_source_owned_position_instead_of_core_commit_lsn
      with_temp_dir do |dir|
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        acknowledgements = []
        work = core_event(source_position: "11")
        coordinator = DeliveryProgressCoordinator.new(
          checkpoint_store: checkpoint_store,
          source_name: "local_mammoth",
          slot_name: "mammoth_prod",
          publication_name: "mammoth_publication",
          acknowledger: acknowledgements.method(:<<),
          position_resolver: ->(_item) { "0/2A" }
        )
        coordinator.register(work, group_end: true)

        coordinator.complete(work)

        assert_equal "0/2A", checkpoint(checkpoint_store).fetch("last_lsn")
        assert_equal ["0/2A"], acknowledgements
      end
    end

    def test_rejects_completion_that_was_not_registered
      with_coordinator do |coordinator, _checkpoint_store, _acknowledgements|
        error = assert_raises(ReplicationError) { coordinator.complete(core_event) }

        assert_match(/before registration/, error.message)
      end
    end

    def test_finalize_closes_a_partially_registered_final_group
      with_coordinator do |coordinator, checkpoint_store, acknowledgements|
        work = core_event(source_position: "0/F")
        coordinator.register(work, group_end: false)
        coordinator.complete(work)

        assert_equal "0/F", coordinator.finalize
        assert_equal "0/F", checkpoint(checkpoint_store).fetch("last_lsn")
        assert_equal ["0/F"], acknowledgements
      end
    end

    def test_removes_completed_work_without_a_source_position
      with_temp_dir do |dir|
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        coordinator = build_coordinator(checkpoint_store, acknowledger: nil)
        work = Object.new
        coordinator.register(work, group_end: true)

        assert_nil coordinator.complete(work)
        assert_equal 0, checkpoint_store.count
      end
    end

    def test_tracks_repeated_registration_of_the_same_work_object
      with_coordinator do |coordinator, checkpoint_store, acknowledgements|
        work = core_event(source_position: "0/10")
        coordinator.register(work, group_end: false)
        coordinator.register(work, group_end: true)

        coordinator.complete(work)
        assert_equal 0, checkpoint_store.count

        coordinator.complete(work)
        assert_equal "0/10", checkpoint(checkpoint_store).fetch("last_lsn")
        assert_equal ["0/10"], acknowledgements
      end
    end

    private

    def with_coordinator
      with_temp_dir do |dir|
        checkpoint_store = CheckpointStore.new(SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!)
        acknowledgements = []
        yield build_coordinator(checkpoint_store, acknowledger: acknowledgements.method(:<<)),
              checkpoint_store, acknowledgements
      end
    end

    def build_coordinator(checkpoint_store, acknowledger:, logger: Logging::NullLogger::INSTANCE)
      DeliveryProgressCoordinator.new(
        checkpoint_store: checkpoint_store,
        source_name: "local_mammoth",
        slot_name: "mammoth_prod",
        publication_name: "mammoth_publication",
        acknowledger: acknowledger,
        logger: logger
      )
    end

    def checkpoint(checkpoint_store)
      checkpoint_store.fetch(source_name: "local_mammoth", slot_name: "mammoth_prod")
    end
  end
  # rubocop:enable Metrics/ClassLength
end
