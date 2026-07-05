# frozen_string_literal: true

require "test_helper"

module Mammoth
  class DeliveredEnvelopeStoreTest < Minitest::Test
    def test_records_and_detects_delivered_envelope
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeliveredEnvelopeStore.new(sqlite)

        refute store.delivered?("source:slot:webhook:tx:0/1")

        store.record!(
          idempotency_key: "source:slot:webhook:tx:0/1",
          source_name: "source",
          slot_name: "slot",
          destination_name: "webhook",
          delivery_unit: "transaction",
          transaction_id: "tx",
          source_position: "0/1"
        )

        assert store.delivered?("source:slot:webhook:tx:0/1")
        assert_equal 1, store.count
      end
    end

    def test_record_is_idempotent
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeliveredEnvelopeStore.new(sqlite)

        2.times do
          store.record!(
            idempotency_key: "same",
            source_name: "source",
            slot_name: "slot",
            destination_name: "webhook",
            delivery_unit: "transaction",
            transaction_id: "tx",
            source_position: "0/1"
          )
        end

        assert_equal 1, store.count
      end
    end

    def test_counts_by_destination
      with_temp_dir do |dir|
        sqlite = SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
        store = DeliveredEnvelopeStore.new(sqlite)
        record(store, destination_name: "primary_webhook", idempotency_key: "primary")
        record(store, destination_name: "audit_webhook", idempotency_key: "audit")

        assert_equal 1, store.count(destination: "audit_webhook")
        assert_equal(
          { "audit_webhook" => 1, "primary_webhook" => 1 },
          store.counts_by_destination.to_h { |row| [row.fetch("destination_name"), row.fetch("count")] }
        )
      end
    end

    private

    def record(store, destination_name:, idempotency_key:)
      store.record!(
        idempotency_key: idempotency_key,
        source_name: "source",
        slot_name: "slot",
        destination_name: destination_name,
        delivery_unit: "transaction",
        transaction_id: "tx",
        source_position: "0/1"
      )
    end
  end
end
