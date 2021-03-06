# coding: UTF-8
# NOTE Code Coverage block must be issued before any of your application code is required
if ENV['BBFS_COVERAGE']
  require_relative '../spec_helper.rb'
  SimpleCov.command_name 'content_data'
end
require 'rspec'
require 'tempfile'
require 'time.rb'
require 'content_server/server'
require_relative '../../lib/content_data/content_data.rb'

describe 'Content Data Test' do

  before :all do
  Params.init Array.new
  # must preced Log.init, otherwise log containing default values will be created
  Params['log_write_to_file'] = false
  Log.init
  end

  it 'test cloning db 1' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 1242, "server_1",
            "/home/file_1", 2222222222)
    content_data.add_symlink("server_1", "/home/link_1", "/home/file_1")

    content_data_cloned = ContentData::ContentData.new(content_data)
    #check that DBs are equal
    content_data_cloned.should == content_data
    content_data_cloned.get_instance_mod_time("A1", ["server_1", "/home/file_1"]).should == 2222222222
    content_data_cloned.each_symlink { |server, path, target|
      [server, path, target].should == ["server_1", "/home/link_1", "/home/file_1"]
    }

    content_data.add_instance("A1", 1242, "server_1",
                  "/home/file_2", 3333333333)
    content_data.add_symlink("server_1", "/home/link_2", "/home/file_1")
    content_data.get_instance_mod_time("A1", ["server_1", "/home/file_2"]).should == 3333333333

    #change orig DB - size
    content_data_cloned.should_not == content_data

    # Check original have not changed...
    content_data_cloned.get_instance_mod_time("A1", ["server_1", "/home/file_2"]).should == nil
    content_data_cloned.each_symlink { |server, path, target|
      [server, path, target].should_not == ["server_1", "/home/link_2", "/home/file_1"]
    }
  end

  it 'test cloning db 2' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 1242, "server_1",
            "/home/file_1", 2222222222)

    content_data_cloned = ContentData::ContentData.new(content_data)
    #check that DBs are equal
    content_data_cloned.should == content_data

    content_data_cloned.add_instance("A2", 1243, "server_1",
             "/home/file_2", 3333333333)
    #change orig DB - size
    content_data_cloned.should_not == content_data
  end


  it 'test add instance' do
    #create first content with instance
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 50, "server_1",
            "/home/file_1", 2222222222)

    #Add new instance - different size
    # size would be overriden should not be added
    content_data.add_instance("A1", 60, "server_1",
            "/home/file_2", 2222222222)
    expected = "1\nA1,60,2222222222\n2\nA1,60,server_1,/home/file_1,2222222222\nA1,60,server_1,/home/file_2,2222222222\n0\n"
    content_data.to_s.should == expected

    #Add new instance - new content
    #both new content and new instances are created in DB
    content_data.add_instance("A2", 60, "server_1",
            "/home/file_2", 3333333333)
    expected = "2\nA1,60,2222222222\nA2,60,3333333333\n2\n" +
  "A1,60,server_1,/home/file_1,2222222222\n" +
  "A2,60,server_1,/home/file_2,3333333333\n" +
        "0\n"
    content_data.to_s.should == expected

  #Add new instance - same content
    content_data.add_instance("A2", 60, "server_1",
            "/home/file_3", 4444444444)
    expected = "2\nA1,60,2222222222\nA2,60,3333333333\n3\n" +
  "A1,60,server_1,/home/file_1,2222222222\n" +
  "A2,60,server_1,/home/file_2,3333333333\n" +
  "A2,60,server_1,/home/file_3,4444444444\n" +
        "0\n"
    content_data.to_s.should == expected
  end

  it 'test instance exists' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A129", 50, "server_1",
            "/home/file_1", 2222222222)
    content_data.instance_exists('/home/file_1', 'server_1').should == true
    content_data.instance_exists('/home/file_1', 'stum').should == false
  end

  it 'test remove instance' do
    #remove instance also removes content
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 50, "server_1",
            "/home/file_1", 2222222222)
    content_data.content_exists('A1').should == true
    content_data.instance_exists('/home/file_1', 'server_1').should == true
    content_data.remove_instance('server_1', '/home/file_1')
    content_data.instance_exists('/home/file_1', 'server_1').should == false
    content_data.content_exists('A1').should == false

    #remove instance does not remove content
    content_data.add_instance("A1", 50, "server_1",
            "/home/file_1", 2222222222)
    content_data.add_instance("A1", 50, "server_1",
            "/home/file_2", 3333333333)
    content_data.content_exists('A1').should == true
    content_data.instance_exists('/home/file_1', 'server_1').should == true
    content_data.remove_instance('server_1', '/home/file_1')
    content_data.instance_exists('/home/file_1', 'server_1').should == false
    content_data.content_exists('A1').should == true

    #remove also removes content
    content_data.remove_instance('server_1', '/home/file_2')
    content_data.instance_exists('/home/file_1', 'server_1').should == false
    content_data.content_exists('A1').should == false
  end

  it 'test to file from file' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 50, "server_1",
            "/home/file_1", 22222222222)
    content_data.add_instance("B1", 60, "server_1",
            "/home/file_2", 44444444444)
    content_data.add_instance("B1", 60, "server_1",
            "/home/file_3", 55555555555)
    content_data.add_symlink("A1", "/home/symlink_1", "home/file_1")
    content_data.add_symlink("B1", "/home/symlink_2", "home/file_xxx")
    content_data.add_symlink("B1", "/home/symlink_1", "home/file_3")
    file_moc_object = StringIO.new
    file_moc_object.write(content_data.to_s)
    test_file = Tempfile.new('content_data_spec.test')
    content_data.to_file(test_file.path)
    content_data_2 = ContentData::ContentData.new
    content_data_2.from_file(test_file.path)
    (content_data == content_data_2).should == true
  end

  it 'test to file from file (zip)' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 50, "server_1",
                              "/home/file_1", 22222222222)
    content_data.add_instance("B1", 60, "server_1",
                              "/home/file_2", 44444444444)
    content_data.add_instance("B1", 60, "server_1",
                              "/home/file_3", 55555555555)
    content_data.add_symlink("A1", "/home/symlink_1", "home/file_1")
    content_data.add_symlink("B1", "/home/symlink_2", "home/file_xxx")
    content_data.add_symlink("B1", "/home/symlink_1", "home/file_3")
    file_moc_object = StringIO.new
    file_moc_object.write(content_data.to_s)
    test_file = Tempfile.new('content_data_spec.test.gz')
    content_data.to_file(test_file.path)
    content_data_2 = ContentData::ContentData.new
    content_data_2.from_file(test_file.path)
    (content_data == content_data_2).should == true
  end

  it 'test old format with comma' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A1", 50, "server_1",
              "/home/file,<><,ласкдфй_1", 22222222222)
    content_data.add_instance("B1", 60, "server_1",
              "/home/filךלחת:,!גדכשe_2", 44444444444)
    content_data.add_instance("B1", 60, "server_1",
              "/home/filкакакаe_3", 55555555555)
    content_data.add_symlink("A1", "/home/syласдфйmlink_1", "home/file_1")
    content_data.add_symlink("B1", "/home/symlinkדגכע_2", "home/file_xxx")
    content_data.add_symlink("B1", "/home/symlinkדכע_1", "home/filкакакаe_3")
    file_moc_object = StringIO.new
    file_moc_object.write(content_data.to_s)
    test_file = Tempfile.new('content_data_spec.test')
    content_data.to_file_old(test_file.path)
    content_data_2 = ContentData::ContentData.new
    content_data_2.from_file_old(test_file.path)
    (content_data == content_data_2).should == true
  end

  it 'test merge' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)

    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_2", 44444444444)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_3", 55555555555)
    content_data_merged = ContentData.merge(content_data_a, content_data_b)
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_merged.to_s.should == expected
    content_data_a.remove_instance('server_1', '/home/file_1')
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_merged.to_s.should == expected
    content_data_b.remove_instance('server_1', '/home/file_2')
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_merged.to_s.should == expected
  end

  it 'test merge override b' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)

    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_2", 44444444444)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_3", 55555555555)
    content_data_merged = ContentData.merge_override_b(content_data_a, content_data_b)
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
  "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_merged.to_s.should == expected

    content_data_a.remove_instance('server_1', '/home/file_1')
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
  "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_merged.to_s.should == expected
    content_data_b.remove_instance('server_1', '/home/file_2')
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "2\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_b.to_s.should == expected

    (content_data_merged == content_data_b).should == true
  end

  it 'test remove' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)

    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)
    content_data_b.add_instance("A1", 50, "server_1",
        "extra_inst", 66666666666)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_2", 44444444444)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_3", 55555555555)
    content_data_removed = ContentData.remove(content_data_a, content_data_b)
    expected =  "1\n" +
        "B1,60,44444444444\n" +
        "2\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected
    content_data_a.remove_instance('server_1', '/home/file_1')
    expected =  "1\n" +
        "B1,60,44444444444\n" +
        "2\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected
    content_data_b.remove_instance('server_1', '/home/file_2')
    expected =  "1\n" +
        "B1,60,44444444444\n" +
        "2\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected

    #check nil
    content_data_removed = ContentData.remove(nil, content_data_b)
    content_data_b.to_s.should == content_data_removed.to_s
    content_data_removed = ContentData.remove(content_data_b, nil)
    nil.should == content_data_removed
  end

  it 'test remove instances' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)

    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)
    content_data_b.add_instance("A1", 50, "server_1",
        "extra_inst", 66666666666)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_2", 44444444444)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_3", 55555555555)
    content_data_removed = ContentData.remove_instances(content_data_a, content_data_b)
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,extra_inst,66666666666\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
  "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected
    content_data_a.remove_instance('server_1', '/home/file_1')
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,extra_inst,66666666666\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
  "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected
    content_data_b.remove_instance('server_1', '/home/file_2')
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,extra_inst,66666666666\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
  "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected

    #nil.should == content_data_b

    #check nil
    content_data_removed = ContentData.remove_instances(nil, content_data_b)
    content_data_b.to_s.should == content_data_removed.to_s
    content_data_removed = ContentData.remove_instances(content_data_b, nil)
    content_data_removed.should == nil
  end

  it 'test remove instances!' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
                                "/home/file_1", 22222222222)

    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("A1", 50, "server_1",
                                "/home/file_1", 22222222222)
    content_data_b.add_instance("A1", 50, "server_1",
                                "extra_inst", 66666666666)
    content_data_b.add_instance("B1", 60, "server_1",
                                "/home/file_2", 44444444444)
    content_data_b.add_instance("B1", 60, "server_1",
                                "/home/file_3", 55555555555)
    content_data_removed = ContentData.remove_instances(content_data_a, content_data_b)
    expected = "2\n" +
        "A1,50,22222222222\n" +
        "B1,60,44444444444\n" +
        "3\n" +
        "A1,50,server_1,extra_inst,66666666666\n" +
        "B1,60,server_1,/home/file_2,44444444444\n" +
        "B1,60,server_1,/home/file_3,55555555555\n" +
        "0\n"
    content_data_removed.to_s.should == expected
    ContentData.remove_instances!(content_data_a, content_data_b)
    content_data_removed.to_s.should == content_data_b.to_s


    #check nil
    content_data_b_cloned = ContentData::ContentData.new(content_data_b)
    ContentData.remove_instances!(nil, content_data_b)
    content_data_b_cloned.to_s.should == content_data_b.to_s
    ContentData.remove_instances!(content_data_b, nil).should == nil

    #check remove all instances
    ContentData.remove_instances!(content_data_b, content_data_b)
    content_data_b.to_s.should == "0\n0\n0\n"
  end

  it 'test remove directory' do
    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("A1", 50, "server_1",
        "/a/b/c/a/b/c/file_1", 22222222222)
    content_data_b.add_instance("A1", 50, "server_1",
        "/a/b/c/extra_inst", 66666666666)
    content_data_b.add_instance("B1", 60, "server_1",
        "/stay/b/c/a/b/c/file_2", 44444444444)
    content_data_b.add_instance("B1", 60, "server_1",
        "/a/b/cc/file_3", 55555555555)
    content_data_b.add_symlink("server_1", "/a/b/c/a/b/c/symlink_1", "/a/b/cc/file_3")
    content_data_b.add_symlink("server_1", "/a/b/c/extra_symlink", "/a/b/c/extra_inst")
    content_data_b.add_symlink("server_1", "/a/a/b/c/stay_symlink", "/a/b/c/extra_inst")
    content_data_removed = ContentData.remove_directory(content_data_b, '/a/b', "server_1")
    expected = "1\n" +
        "B1,60,44444444444\n" +
        "1\n" +
        "B1,60,server_1,/stay/b/c/a/b/c/file_2,44444444444\n" +
        "1\n" +
        "server_1,/a/a/b/c/stay_symlink,/a/b/c/extra_inst\n"
    content_data_removed.to_s.should == expected

    content_data_b.remove_instance('server_1', '/stay/b/c/a/b/c/file_2')
    expected = "1\n" +
        "B1,60,44444444444\n" +
        "1\n" +
        "B1,60,server_1,/stay/b/c/a/b/c/file_2,44444444444\n" +
        "1\n" +
        "server_1,/a/a/b/c/stay_symlink,/a/b/c/extra_inst\n"
    content_data_removed.to_s.should == expected

    expected = "2\nA1,50,22222222222\nB1,60,44444444444\n" +
  "3\n" +
        "A1,50,server_1,/a/b/c/a/b/c/file_1,22222222222\n" +
        "A1,50,server_1,/a/b/c/extra_inst,66666666666\n" +
  "B1,60,server_1,/a/b/cc/file_3,55555555555\n" +
        "3\n" +
        "server_1,/a/a/b/c/stay_symlink,/a/b/c/extra_inst\n" +
        "server_1,/a/b/c/a/b/c/symlink_1,/a/b/cc/file_3\n" +
        "server_1,/a/b/c/extra_symlink,/a/b/c/extra_inst\n"
    content_data_b.to_s.should == expected

    content_data_removed = ContentData.remove_directory(content_data_b, '/kuku', "server_1")
    content_data_removed = ContentData.remove_directory(content_data_b, '/a/b/c', "server_1")
    content_data_removed.contents_size.should == 1
    content_data_removed.to_s.should == "1\n" +
        "B1,60,44444444444\n" +
        "1\n" +
        "B1,60,server_1,/a/b/cc/file_3,55555555555\n" +
        "1\n" +
        "server_1,/a/a/b/c/stay_symlink,/a/b/c/extra_inst\n"

    content_data_removed = ContentData.remove_directory(nil, 'home', "server_1")
    content_data_removed.should == nil
  end

  it 'test intersect' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)
    content_data_a.add_instance("C1", 70, "server_1",
        "/home/file_4", 77777777777)
    content_data_b = ContentData::ContentData.new
    content_data_b.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)
    content_data_b.add_instance("A1", 50, "server_1",
        "/home/file_5", 55555555555)
    content_data_b.add_instance("B1", 60, "server_1",
        "/home/file_2", 44444444444)

    content_data_intersect = ContentData.intersect(content_data_a, content_data_b)
    expected =  "1\n" +
        "A1,50,22222222222\n" +
  "2\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "A1,50,server_1,/home/file_5,55555555555\n" +
        "0\n"
    content_data_intersect.to_s.should == expected
  end

  it 'test get mod time' do
    content_data = ContentData::ContentData.new
    content_data.add_instance("A", 50, "server_1", "/home/file_1", 123)
    content_data.get_instance_mod_time("B", ["server_1", "/home/file_1"]).should == nil
    content_data.get_instance_mod_time("A", ["server_2", "/home/file_1"]).should == nil
    content_data.get_instance_mod_time("A", ["server_1", "/home/file_1"]).should == 123
  end

  it 'test unify time' do
    content_data_a = ContentData::ContentData.new
    content_data_a.add_instance("A1", 50, "server_1",
        "/home/file_1", 22222222222)
    content_data_a.add_instance("C1", 70, "server_1",
        "/home/file_4", 77777777777)
    content_data_a.add_instance("C1", 70, "server_1",
        "/home/file_5", 33333333333)
    content_data_a.unify_time
    expected =  "2\n" +
        "A1,50,22222222222\n" +
        "C1,70,33333333333\n" +
  "3\n" +
        "A1,50,server_1,/home/file_1,22222222222\n" +
        "C1,70,server_1,/home/file_4,33333333333\n" +
  "C1,70,server_1,/home/file_5,33333333333\n" +
        "0\n"
    content_data_a.to_s.should == expected
  end

  describe 'Set operations' do
    before :all do
      SIZE = 1000
      SERVER = "server"
      CHECKSUM = "1000"
      BASE_TIMESTAMP = '2010-11-29T04:01+03:00'
      BASE_DATETIME = DateTime.iso8601(BASE_TIMESTAMP)
      BASE_MTIME = BASE_DATETIME.strftime('%s').to_i
      CHANGED_PATH = "changed_1"

      @other_1 = ContentData::ContentData.new
      @other_1.add_instance(CHECKSUM+"b", SIZE+5, SERVER, "new_1", BASE_MTIME, BASE_MTIME)
      @other_1.add_instance(CHECKSUM+"b", SIZE+5, SERVER, CHANGED_PATH, BASE_MTIME+5, BASE_MTIME+5)
      @other_1.add_instance(CHECKSUM, SIZE, SERVER, "unchanged_1", BASE_MTIME, BASE_MTIME)

      @other_2 = ContentData::ContentData.new
      @other_2.add_instance(CHECKSUM+"c", SIZE+6, SERVER, "new_2", BASE_MTIME, BASE_MTIME)
    end

    before :each do
      @base = ContentData::ContentData.new
      @base.add_instance(CHECKSUM, SIZE, SERVER, "unchanged_1", BASE_MTIME, BASE_MTIME)
      @base.add_instance(CHECKSUM, SIZE, SERVER, CHANGED_PATH, BASE_MTIME, BASE_MTIME)
      @base.add_instance(CHECKSUM+"1", SIZE+1, SERVER, "unchanged_2", BASE_MTIME, BASE_MTIME)
      @base.add_instance(CHECKSUM+"1", SIZE+1, SERVER, "changed_2", BASE_MTIME, BASE_MTIME)
      @base.add_instance(CHECKSUM+"a", SIZE+5, SERVER, "unique_1", BASE_MTIME, BASE_MTIME)
    end

    describe 'Merge' do
      shared_examples 'merge spec' do
        it 'contains instances exist at least in one ContentData' do
          merged_objects.each do |cd|
            cd.each_instance do |_,_,_,_,server,path,_|
              expect(res.instance_exists(path, server)).to be_true
            end
          end
        end

        it 'has only one record for the location' do
          locations = []
          res.each_instance do |_,_,_,_,server,path,_|
            location = [server, path]
            expect(locations.include?(location)).to be_false
            locations << location
          end
        end
      end

      describe 'ContentData::ContentData#merge' do
        context 'parameter is a single ContentData object' do
          let!(:res) { @base.merge(@other_1) }
          let(:merged_objects) { [@base, @other_1] }
          include_examples 'merge spec'
        end

        context 'parameter is a list of ContentData objects' do
          let!(:res) { @base.merge(@other_1, @other_2) }
          let(:merged_objects) { [@base, @other_1, @other_2] }
          include_examples 'merge spec'
        end

        context 'parameter is an array of ContentData objects' do
          let!(:res) { @base.merge([@other_1, @other_2]) }
          let(:merged_objects) { [@base, @other_1, @other_2] }
          include_examples 'merge spec'
        end
      end

      describe 'ContentData::ContentData#merge!' do
        context 'parameter is a single ContentData object' do
          let!(:res) { new_cd = ContentData::ContentData.new(@base)
                      new_cd.merge!(@other_1)
                      new_cd }
          let(:merged_objects) { [@base, @other_1] }
          include_examples 'merge spec'
        end

        context 'parameter is a list of ContentData objects' do
          let!(:res) { new_cd = ContentData::ContentData.new(@base)
                      new_cd.merge!(@other_1, @other_2)
                      new_cd }
          let(:merged_objects) { [@base, @other_1, @other_2] }
          include_examples 'merge spec'
        end

        context 'parameter is an array of ContentData objects' do
          let!(:res) { new_cd = ContentData::ContentData.new(@base)
                      new_cd.merge!([@other_1, @other_2])
                      new_cd }
          let(:merged_objects) { [@base, @other_1, @other_2] }
          include_examples 'merge spec'
        end
      end
    end

    describe 'Remove instances' do
      shared_examples 'remove spec' do
        it 'contains (checksum + location) presented only in base' do
          base.each_instance do |checksum,_,_,_,server,path,_|
            other_cd_has_instance = others.find do |cd|
                                      cd.content_has_instance?(checksum, server, path)
                                    end
            if other_cd_has_instance.nil?
              expect(res.content_has_instance?(checksum, server, path)).to be_true
            else
              expect(res.content_has_instance?(checksum, server, path)).to be_false
            end
          end
        end

        context 'Instances with same location and different checksums' do
          it 'defined to be different and thus remain' do
            expect(res.content_has_instance?(CHECKSUM, SERVER, CHANGED_PATH)).
              to be_true
            expect(base.content_has_instance?(CHECKSUM, SERVER, CHANGED_PATH)).
              to be_true

            other_instance_found = false
            others.each do |cd|
              if cd.instance_exists(CHANGED_PATH, SERVER)
                expect(cd.content_has_instance?(CHECKSUM, SERVER, CHANGED_PATH)).
                  to be_false
                other_instance_found = true
              end
            end
            # check that test data was correct,
            # i.e. other ContentData indeed contains same location
            # with different content
            expect(other_instance_found).to be_true
          end
        end
      end

      describe 'ContentData::ContentData#remove_instances' do
        context 'parameter is a single ContentData object' do
          let(:base) { @base }
          let(:res) { @base.remove_instances(@other_1) }
          let(:others) { [@other_1] }
          include_examples 'remove spec'
        end

        context 'parameter is a list of ContentData objects' do
          let(:base) { @base }
          let(:res) { @base.remove_instances(@other_1, @other_2) }
          let(:others) { [@other_1, @other_2] }
          include_examples 'remove spec'
        end

        context 'parameter is an array of ContentData objects' do
          let(:base) { @base }
          let(:res) { @base.remove_instances([@other_1, @other_2]) }
          let(:others) { [@other_1, @other_2] }
          include_examples 'remove spec'
        end
      end

      describe 'ContentData::ContentData#remove_instances!' do
        context 'parameter is a single ContentData object' do
          let!(:base) { ContentData::ContentData.new(@base) }
          let(:res) { @base.remove_instances(@other_1) }
          let(:others) { [@other_1] }
          include_examples 'remove spec'
        end

        context 'parameter is a list of ContentData objects' do
          let!(:base) { ContentData::ContentData.new(@base) }
          let(:res) { @base.remove_instances(@other_1, @other_2) }
          let(:others) { [@other_1, @other_2] }
          include_examples 'remove spec'
        end

        context 'parameter is an array of ContentData objects' do
          let!(:base) { ContentData::ContentData.new(@base) }
          let(:res) { @base.remove_instances([@other_1, @other_2]) }
          let(:others) { [@other_1, @other_2] }
          include_examples 'remove spec'
        end
      end
    end
  end
end

