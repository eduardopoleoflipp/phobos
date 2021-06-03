module Phobos
  class RoundRobinAssignmentStrategy
    def protocol_name
      "roundrobin"
    end

    # Assign the topic partitions to the group members.
    #
    # @param cluster [Kafka::Cluster]
    # @param members [Hash<String, Kafka::Protocol::JoinGroupResponse::Metadata>] a hash
    #   mapping member ids to metadata
    # @param partitions [Array<Kafka::ConsumerGroup::Assignor::Partition>] a list of
    #   partitions the consumer group processes
    # @return [Hash<String, Array<Kafka::ConsumerGroup::Assignor::Partition>] a hash
    #   mapping member ids to partitions.
    def call(cluster:, members:, partitions:)
      partitions_per_member = Hash.new {|h, k| h[k] = [] }
      relevant_partitions = valid_sorted_partitions(members, partitions)
      members_ids = members.keys
      idx = 0

      relevant_partitions.each do |partition|
        topic = partition.topic

        while !members[members_ids[idx]].topics.include?(topic)
          idx = next_index(members_ids, idx)
        end

        partitions_per_member[members_ids[idx]] << partition
        idx = next_index(members_ids, idx)
      end

      partitions_per_member
    end

    def valid_sorted_partitions(members, partitions)
      subscribed_topics = members.map { |id, metadata| metadata&.topics }.flatten.compact
      partitions
        .select { |partition| subscribed_topics.include?(partition.topic) }
        .sort_by { |partition| partition.topic }
    end

    def next_index(members_ids, idx)
      idx += 1
      idx = 0 if idx == members_ids.size

      idx
    end
  end
end
