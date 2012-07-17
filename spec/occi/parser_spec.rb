require "rspec"
require 'occi/parser'

describe "Parser" do

  it "should parse OCCI message with entity in text plain format" do
    media_type = 'text/plain'
    body       = %Q|Category: compute; scheme="http://schemas.ogf.org/occi/infrastructure#"; class="kind"\nX-OCCI-Attribute: occi.compute.cores=2|
    locations, collection = OCCI::Parser.parse(media_type, body)
  end

  it "should parse an OVA container" do
    media_type = 'application/ova'
    body       = File.read('spec/occi/test.ova')
    locations, collection = OCCI::Parser.parse(media_type, body)
    storage_resources = collection.resources.select { |resource| resource.kind == 'http://schemas.ogf.org/occi/infrastructure#storage' }
    storage_resources.should have(1).storage_resource
    storage_resources.first.attributes.occi!.core!.title.should == 'lamp'
    network_resources = collection.resources.select { |resource| resource.kind == 'http://schemas.ogf.org/occi/infrastructure#network' }
    network_resources.should have(1).network_resource
    network_resources.first.attributes.occi!.core!.title.should == 'VM Network'
    compute_resources = collection.resources.select { |resource| resource.kind == 'http://schemas.ogf.org/occi/infrastructure#compute' }
    compute_resources.should have(1).compute_resource
    compute_resources.first.attributes.occi!.compute!.cores.should == 1
    compute_resources.first.attributes.occi!.compute!.memory.should == 256
  end
end