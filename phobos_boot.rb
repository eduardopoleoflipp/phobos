puts 'hello'

class MyHandler1
  include Phobos::Handler

  def consume(payload, metadata)
    puts '$$$$$$ HANDLER1 $$$$$$$$$'
    puts "#{Thread.current.object_id}"
    puts "#{metadata}"
  end
end

class MyHandler2
  include Phobos::Handler

  def consume(payload, metadata)
    puts '$$$$$$ HANDLER2 $$$$$$$$$'
    puts "#{Thread.current.object_id}"
    puts "#{metadata}"
  end
end

class MyHandler3
  include Phobos::Handler

  def consume(payload, metadata)
    puts '$$$$$$ HANDLER3 $$$$$$$$$'
    puts "#{Thread.current.object_id}"
    puts "#{metadata}"
  end
end