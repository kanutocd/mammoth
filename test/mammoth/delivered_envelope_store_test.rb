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
  end
end
