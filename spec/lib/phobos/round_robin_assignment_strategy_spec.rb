# frozen_string_literal: true

require 'spec_helper'

describe Phobos::RoundRobinAssignmentStrategy do
  let(:strategy) { described_class.new }

  # We need to ensure that the new strategy is backwards compatible
  # with the previous one. The following tests were backported from the
  # ruby-kafka library directly to prove that.
  context 'ruby-kafka RoundRobinAssignmentStrategy specs' do
    it "assigns all partitions" do
      members = Hash[(0...10).map {|i| ["member#{i}", double(topics: ['greetings'])] }]
      partitions = (0...30).map {|i| double(:"partition#{i}", topic: "greetings", partition_id: i) }

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      partitions.each do |partition|
        member = assignments.values.find {|assigned_partitions|
          assigned_partitions.find {|assigned_partition|
            assigned_partition == partition
          }
        }

        expect(member).to_not be_nil
      end
    end

    it "spreads all partitions between members" do
      topics = ["topic1", "topic2"]
      members = Hash[(0...10).map {|i| ["member#{i}", double(topics: topics)] }]
      partitions = topics.product((0...5).to_a).map {|topic, i|
        double(:"partition#{i}", topic: topic, partition_id: i)
      }

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      partitions.each do |partition|
        member = assignments.values.find {|assigned_partitions|
          assigned_partitions.find {|assigned_partition|
            assigned_partition == partition
          }
        }

        expect(member).to_not be_nil
      end

      num_partitions_assigned = assignments.values.map do |assigned_partitions|
        assigned_partitions.count
      end

      expect(num_partitions_assigned).to all eq(1)
    end

    Metadata = Struct.new(:topics)
    [
      {
        name: "uneven topics",
        topics: { "topic1" => [0], "topic2" => (0..50).to_a },
        members: {
          "member1" => Metadata.new(["topic1", "topic2"]),
          "member2" => Metadata.new(["topic1", "topic2"])
        },
      },
      {
        name: "only one partition",
        topics: { "topic1" => [0] },
        members: {
          "member1" => Metadata.new(["topic1"]),
          "member2" => Metadata.new(["topic1"])
        },
      },
      {
        name: "lots of partitions",
        topics: { "topic1" => (0..100).to_a },
        members: { "member1" => Metadata.new(["topic1"]) },
      },
      {
        name: "lots of members",
        topics: { "topic1" => (0..10).to_a, "topic2" => (0..10).to_a },
        members: Hash[(0..50).map { |i| ["member#{i}", Metadata.new(["topic1", "topic2"])] }]
      },
      {
        name: "odd number of partitions",
        topics: { "topic1" => (0..14).to_a },
        members: {
          "member1" => Metadata.new(["topic1"]),
          "member2" => Metadata.new(["topic1"])
        },
      },
      {
        name: "five topics, 10 partitions, 3 consumers",
        topics: { "topic1" => [0, 1], "topic2" => [0, 1], "topic3" => [0, 1], "topic4" => [0, 1], "topic5" => [0, 1] },
        members: {
          "member1" => Metadata.new(["topic1", "topic2", "topic3", "topic4", "topic5"]),
          "member2" => Metadata.new(["topic1", "topic2", "topic3", "topic4", "topic5"]),
          "member3" => Metadata.new(["topic1", "topic2", "topic3", "topic4", "topic5"])
        },
      }
    ].each do |options|
      name, topics, members = options[:name], options[:topics], options[:members]
      it name do
        partitions = topics.flat_map {|topic, partition_ids|
          partition_ids.map {|i|
            double(:"partition#{i}", topic: topic, partition_id: i)
          }
        }

        assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

        expect_all_partitions_assigned(topics, assignments)
        expect_even_assignments(topics, assignments)
      end
    end

    def expect_all_partitions_assigned(topics, assignments)
      topics.each do |topic, partition_ids|
        partition_ids.each do |partition_id|
          assigned = assignments.values.find do |assigned_partitions|
            assigned_partitions.find {|assigned_partition|
              assigned_partition.topic == topic && assigned_partition.partition_id == partition_id
            }
          end
          expect(assigned).to_not be_nil
        end
      end
    end

    def expect_even_assignments(topics, assignments)
      num_partitions = topics.values.flatten.count
      assignments.values.each do |assigned_partition|
        num_assigned = assigned_partition.count
        expect(num_assigned).to be_within(1).of(num_partitions.to_f / assignments.count)
      end
    end
  end

  context 'when there is a listener not subscribed to anything' do
    it 'does NOT produces assignments' do
      members = { 'member1' => nil }
      partitions = []

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({}) # is this correct?
    end
  end

  context 'when there is a listener subscription but not matching partition' do
    it 'does NOT produces assignments' do
      members = { 'member1' => double(topics: ['topic1']) }
      partitions = []

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({})
    end
  end

  context 'when there is 1 listener subscribed to 1 topic with 1 partition' do
    it 'assigns the partition to the listener' do
      members = { 'member1' => double(topics: ['topic1']) }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0]
      })
    end
  end

  context 'when there is 1 listener subscribed to 1 topic with multiple partitions' do
    it 'assigns all partitions to the listener' do
      members = { 'member1' => double(topics: ['topic1']) }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition0", topic: "topic1", partition_id: 1),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0, partition1]
      })
    end
  end

  context 'when there is 1 listeners subscribed to 1 topic and there are multiple topic partitions' do
    it 'only assigns partitions for the subscribed topic' do
      members = { 'member1' => double(topics: ['topic1']) }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition0", topic: "topic1", partition_id: 1),
         partition2 = double(:"partition0", topic: "topic2", partition_id: 0),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0, partition1]
      })
    end
  end

  context 'when there are 2 listeners subscribed to 1 topic but only 1 partition' do
    it 'only assigns the partition to 1 listener' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic1'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0]
      })
    end
  end

  context 'when there are 2 listeners subscribed to 1 topic with 2 partitions' do
    it 'each listener gets a partition' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic1'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition1", topic: "topic1", partition_id: 1),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0],
        'member2' => [partition1]
      })
    end
  end

  context 'when there are 2 listeners subscribed to 1 topic with multiple even number of partitions' do
    it 'produces a balanced assignment' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic1'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition1", topic: "topic1", partition_id: 1),
         partition2 = double(:"partition2", topic: "topic1", partition_id: 2),
         partition3 = double(:"partition3", topic: "topic1", partition_id: 3),
         partition4 = double(:"partition4", topic: "topic1", partition_id: 4),
         partition5 = double(:"partition5", topic: "topic1", partition_id: 5),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0, partition2, partition4],
        'member2' => [partition1, partition3, partition5],
      })
    end
  end

  context 'when there are 2 listeners subscribed to 1 topic with multiple odd number of partitions' do
    it 'produces a quasi balanced assignment' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic1'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition1", topic: "topic1", partition_id: 1),
         partition2 = double(:"partition2", topic: "topic1", partition_id: 2),
         partition3 = double(:"partition3", topic: "topic1", partition_id: 3),
         partition4 = double(:"partition4", topic: "topic1", partition_id: 4),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0, partition2, partition4],
        'member2' => [partition1, partition3],
      })
    end
  end

  context 'when there are 2 listeners subscribed to 2 different topics with 1 partition' do
    it 'assigns the partitions to the respective subscribed listeners' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic2'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition1", topic: "topic2", partition_id: 1),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0],
        'member2' => [partition1],
      })
    end
  end

  context 'when there are 2 listener subscribed to 2 different topics with multiple partitions' do
    it 'assigns the partitions to the respective subscribed listeners' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic2'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition2 = double(:"partition1", topic: "topic2", partition_id: 1),
         partition3 = double(:"partition1", topic: "topic2", partition_id: 1),
         partition4 = double(:"partition1", topic: "topic2", partition_id: 1),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments).to eq({
        'member1' => [partition0, partition1],
        'member2' => [partition2, partition3, partition4],
      })
    end
  end

  context 'when there is a mix variety of topic subscriptions and partition counts' do
    it 'produces balanced assignments' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic2']),
        'member3' => double(topics: ['topic2']),
        'member4' => double(topics: ['topic3']),
        'member5' => double(topics: ['topic3']),
        'member6' => double(topics: ['topic3']),
        'member7' => double(topics: ['topic4'])
      }
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition1", topic: "topic1", partition_id: 0),
         partition2 = double(:"partition2", topic: "topic2", partition_id: 1),
         partition3 = double(:"partition3", topic: "topic2", partition_id: 1),
         partition4 = double(:"partition4", topic: "topic2", partition_id: 1),
         partition5 = double(:"partition5", topic: "topic3", partition_id: 1),
         partition6 = double(:"partition6", topic: "topic3", partition_id: 1),
         partition7 = double(:"partition7", topic: "topic3", partition_id: 1),
         partition8 = double(:"partition8", topic: "topic3", partition_id: 1),
         partition9 = double(:"partition9", topic: "topic3", partition_id: 1),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)


      expect(assignments['member1'].size).to eq(2)
      expect(assignments['member1'].map(&:topic).uniq).to eq(['topic1'])

      expect(assignments['member2'].size).to eq(2)
      expect(assignments['member2'].map(&:topic).uniq).to eq(['topic2'])

      expect(assignments['member3'].size).to eq(1)
      expect(assignments['member3'].map(&:topic).uniq).to eq(['topic2'])

      expect(assignments['member4'].size).to eq(2)
      expect(assignments['member4'].map(&:topic).uniq).to eq(['topic3'])

      expect(assignments['member5'].size).to eq(2)
      expect(assignments['member5'].map(&:topic).uniq).to eq(['topic3'])

      expect(assignments['member6'].size).to eq(1)
      expect(assignments['member6'].map(&:topic).uniq).to eq(['topic3'])

      expect(assignments['member7'].size).to eq(0)
    end
  end

  context 'when the partitions are given out of order' do
    it 'produces balanced assignments' do
      members = {
        'member1' => double(topics: ['topic1']),
        'member2' => double(topics: ['topic2']),
        'member3' => double(topics: ['topic2']),
        'member4' => double(topics: ['topic3']),
        'member5' => double(topics: ['topic3']),
        'member6' => double(topics: ['topic3']),
        'member7' => double(topics: ['topic4'])
      }

      # Without sorting the partitions by topic this input would
      # produce an assignment such as:
      # member2 => [partition4, partition3]
      # member3 => []
      # which is not well balanced
      partitions = [
         partition0 = double(:"partition0", topic: "topic1", partition_id: 0),
         partition1 = double(:"partition1", topic: "topic1", partition_id: 0),
         partition4 = double(:"partition4", topic: "topic2", partition_id: 1),
         partition5 = double(:"partition5", topic: "topic3", partition_id: 1),
         partition6 = double(:"partition6", topic: "topic3", partition_id: 1),
         partition7 = double(:"partition7", topic: "topic3", partition_id: 1),
         partition8 = double(:"partition8", topic: "topic3", partition_id: 1),
         partition3 = double(:"partition3", topic: "topic2", partition_id: 1),
         partition9 = double(:"partition9", topic: "topic3", partition_id: 1),
      ]

      assignments = strategy.call(cluster: nil, members: members, partitions: partitions)

      expect(assignments['member1'].size).to eq(2)
      expect(assignments['member1'].map(&:topic).uniq).to eq(['topic1'])

      expect(assignments['member2'].size).to eq(1)
      expect(assignments['member2'].map(&:topic).uniq).to eq(['topic2'])

      expect(assignments['member3'].size).to eq(1)
      expect(assignments['member3'].map(&:topic).uniq).to eq(['topic2'])

      expect(assignments['member4'].size).to eq(2)
      expect(assignments['member4'].map(&:topic).uniq).to eq(['topic3'])

      expect(assignments['member5'].size).to eq(2)
      expect(assignments['member5'].map(&:topic).uniq).to eq(['topic3'])

      expect(assignments['member6'].size).to eq(1)
      expect(assignments['member6'].map(&:topic).uniq).to eq(['topic3'])

      expect(assignments['member7'].size).to eq(0)
    end
  end
end
