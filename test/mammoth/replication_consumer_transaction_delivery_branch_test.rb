# frozen_string_literal: true

require "test_helper"

module Mammoth
  class ReplicationConsumerTransactionDeliveryBranchTest < Minitest::Test
    def test_transaction_delivery_falls_back_to_commit_lsn_identity
      event = CDC::Core::ChangeEvent.new(
        operation: :insert,
        schema: "public",
        table: "orders",
        commit_lsn: "0/100"
      )

      envelope = ReplicationConsumer.new(source: [event], delivery_unit: :transaction).start.to_a.fetch(0)

      assert_instance_of CDC::Core::TransactionEnvelope, envelope
      assert_equal "0/100", envelope.transaction_id
    end
  end
end
