require 'rubygems'
require 'uuidtools'
require 'occi/core/Attribute'
require 'occi/core/Attributes'
require 'occi/core/Kind'

module OCCI
  module Core
    class Entity

      attr_reader :kind_type

      # Define appropriate kind
      begin
        actions     = []
        related     = []
        entity_type = self
        entities    = []

        term    = "entity"
        scheme  = "http://schemas.ogf.org/occi/core#"
        title   = "Entity"

        attributes = OCCI::Core::Attributes.new()
        attributes << OCCI::Core::Attribute.new(name = 'occi.core.id',    mutable = false,  mandatory = true,   unique = true)
        attributes << OCCI::Core::Attribute.new(name = 'occi.core.title', mutable = true,   mandatory = false,  unique = true)
          
        KIND = OCCI::Core::Kind.new(actions, related, entity_type, entities, term, scheme, title, attributes)
      end

      # attributes are hashes and contain key - value pairs as defined by the corresponding kind
      attr_accessor :attributes
      attr_reader   :mixins

      def initialize(attributes)
        # create UUID from namespace using SHA-1
#        attributes['occi.core.id'] = UUIDTools::UUID.sha1_create(UUIDTools::UUID_DNS_NAMESPACE, $config['server']).to_s
        # Make sure UUID is UNIQUE for every entity
        attributes['occi.core.id'] = UUIDTools::UUID.timestamp_create.to_s
        attributes['occi.core.title'] = "" if attributes['occi.core.title'] == nil
        @attributes = attributes
        @mixins = []
        @kind_type = "http://schemas.ogf.org/occi/core#entity"
        kind.entities << self
      end
      
      def delete()
        $log.debug("Deleting entity with location #{get_location}")
        delete_entity()
      end
      
      def delete_entity()
        self.mixins.each do |mixin|
          mixin.entities.delete(self)
        end
        # remove all links from this entity and from all linked entities
        links = @attributes['links'].clone() if @attributes['links'] != nil
        links.each do |link|
          $log.debug("occi.core.target #{link.attributes["occi.core.target"]}")
          target_uri = URI.parse(link.attributes["occi.core.target"])
          target = $locationRegistry.get_object_by_location(target_uri.path) 
          $log.debug("Target #{target}")
          target.attributes['links'].delete(link)

          $log.debug("occi.core.source #{link.attributes["occi.core.source"]}")
          source_uri = URI.parse(link.attributes["occi.core.source"])
          source = $locationRegistry.get_object_by_location(source_uri.path) 
          $log.debug("Source #{source}")
          source.attributes['links'].delete(link)
        end if links != nil
        kind.entities.delete(self)
        $locationRegistry.unregister_location(get_location())
      end
      
      def get_location()
        location = $locationRegistry.get_location_of_object(kind) + attributes['occi.core.id']
      end
      
      def get_category_string()
        self.class.getKind.get_short_category_string()
      end

#      def associate_mixin(mixin)
#        raise "Can not associate 'nil'-mixin with entity: #{self}"
#        @mixin = mixin
#        attributes = self.add_mixin_attributes
#        mix_entities = @mixin.addEntity(self)
#        @mixins << @mixin
#      end

      #TODO: also the actions has to be merged
#      def add_mixin_attributes
#        @attributes.merge!(@mixin.get_attributes())
#        mixin_orig = @mixin
#        while @mixin.related != nil
#          @mixin = @mixin.related
#          @attributes.merge!(@mixin.get_attributes())
#        end
#        @mixin = mixin_orig
#        @attributes
#      end

#      def get_own_attributes()
#        attr = []
#        self.class.getKind().attributes.keys.each do |key|    
#          attr << key + '=' + @attributes[key] if @attributes[key] != nil
#        end
#        return attr
#      end

      def kind()
        return $categoryRegistry.getKind(@kind_type)
      end


    end
  end
end