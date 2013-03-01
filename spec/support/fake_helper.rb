module Fake
  module FakeMethods
    def fake_client(attributes = {})
      CFoundry::V2::FakeClient.new.fake(attributes)
    end

    def fake(what, attributes = {})
      fake_client.send(what).fake(attributes)
    end

    def fake_list(what, count, attributes = {})
      objs = []

      count.times do
        objs << fake(what, attributes)
      end

      objs
    end

    def fake_model(name = :my_fake_model, &init)
      # There is a difference between ruby 1.8.7 and 1.8.8 in the order that
      # the inherited callback gets called. In 1.8.7 the inherited callback
      # is called after the block; in 1.8.8 and later it's called before.
      # The upshot for us is we need a failproof way of getting the name
      # to klass. So we're using a global variable to hand off the value.
      # Please don't shoot us. - ESH & MMB
      $object_name = name
      klass = Class.new(CFoundry::V2::FakeModel) do
        self.object_name = name
      end

      klass.class_eval(&init) if init

      klass
    end
  end

  def fake(attributes = {})
    fake_attributes(attributes).each do |k, v|
      send(:"#{k}=", v)
      setup_reverse_relationship(v)
    end

    self
  end

  def self.define_many_association(target, plural)
    target.class_eval do
      define_method(plural) do |*args|
        options, _ = args
        options ||= {}

        vals = get_many(plural) || []

        if options[:query]
          by, val = options[:query]
          vals.select do |v|
            v.send(by) == val
          end
        else
          vals
        end
      end
    end
  end
end

module CFoundry::V2
  class FakeBase < Base
  end


  class FakeClient < Client
    include Fake

    def initialize(target = "http://example.com", token = nil)
      @base = FakeBase.new(target, token)
    end

    private

    def get_many(plural)
      instance_variable_get(:"@#{plural}")
    end

    def fake_attributes(attributes)
      attributes
    end

    def setup_reverse_relationship(v)
      if v.is_a?(Model)
        v.client = self
      elsif v.is_a?(Array)
        v.each do |x|
          setup_reverse_relationship(x)
        end
      end
    end
  end


  module ModelFakes
    include Fake

    def self.included(klass)
      klass.class_eval do
        attr_writer :client
        attr_reader :diff
      end

      class << klass
        attr_writer :object_name
      end
    end

    private

    def get_many(plural)
      @cache[plural]
    end

    def fake_attributes(attributes)
      fakes = default_fakes

      # default relationships to other fake objects
      self.class.to_one_relations.each do |name, opts|
        # remove _guid (not an actual attribute)
        fakes.delete :"#{name}_guid"
        next if fakes.key?(name)

        fakes[name] =
          if opts.key?(:default)
            opts[:default]
          else
            @client.send(opts[:as] || name).fake
          end
      end

      # make sure that the attributes provided are set after the defaults
      #
      # we have to do this for cases like environment_json vs. env,
      # where one would clobber the other
      attributes.each do |k, _|
        fakes.delete k
      end

      fakes = fakes.to_a
      fakes += attributes.to_a

      fakes
    end

    # override this to provide basic attributes (like name) dynamically
    def default_fakes
      self.class.defaults.merge(
        :guid => random_string("fake-#{object_name}-guid"))
    end

    def setup_reverse_relationship(v)
      if v.is_a?(Array)
        v.each do |x|
          setup_reverse_relationship(x)
        end

        return
      end

      return unless v.is_a?(Model)

      relation, type = find_reverse_relationship(v)

      v.client = @client

      if type == :one
        v.send(:"#{relation}=", self)
      elsif type == :many
        v.send(:"#{relation}=", v.send(relation) + [self])
      end
    end

    def find_reverse_relationship(v)
      singular = object_name
      plural = plural_object_name

      v.class.to_one_relations.each do |attr, opts|
        return [attr, :one] if attr == singular
        return [attr, :one] if opts[:as] == singular
      end

      v.class.to_many_relations.each do |attr, opts|
        return [attr, :many] if attr == plural
        return [attr, :many] if opts[:as] == singular
      end
    end
  end

  class FakeModel < Model
    include ModelFakes

    def self.inherited(klass)
      class << klass
        attr_writer :object_name
      end

      # There is a difference between ruby 1.8.7 and 1.8.8 in the order that
      # the inherited callback gets called. In 1.8.7 the inherited callback
      # is called after the block; in 1.8.8 and later it's called before.
      # The upshot for us is we need a failproof way of getting the name
      # to klass. So we're using a global variable to hand off the value.
      # Please don't shoot us. - ESH & MMB
      klass.object_name = $object_name
      super
    end
  end


  module FakeModelMagic
    def self.define_client_methods(&blk)
      # TODO
      FakeClient.module_eval(&blk)
    end

    def self.define_base_client_methods(&blk)
      # TODO
      FakeBase.module_eval(&blk)
    end
  end


  class FakeModel
    extend FakeModelMagic
  end


  class Model
    class << self
      attr_writer :object_name
    end
  end

  Model.objects.each_value do |klass|
    name = "Fake" + klass.name.split("::").last

    # There is a difference between ruby 1.8.7 and 1.8.8 in the order that
    # the inherited callback gets called. In 1.8.7 the inherited callback
    # is called after the block; in 1.8.8 and later it's called before.
    # The upshot for us is we need a failproof way of getting the name
    # to klass. So we're using a global variable to hand off the value.
    # Please don't shoot us. - ESH & MMB
    $object_name = name
    fake = Class.new(klass) do
      self.object_name =
        name.split("::").last.gsub(
          /([a-z])([A-Z])/,
          '\1_\2').downcase.to_sym
    end

    fake.class_eval do
      include ModelFakes

      attr_writer :client

      klass.attributes.each do |attr, (type, opts)|
        attribute attr, type, opts
      end

      klass.to_many_relations.each do |many, _|
        Fake.define_many_association(self, many)
      end

      klass.to_one_relations.each do |one, opts|
        to_one one, opts
      end
    end

    const_set(name, fake)

    FakeClient.class_eval do
      plural = klass.plural_object_name

      attr_writer plural
      Fake.define_many_association(self, plural)

      define_method(klass.object_name) do |*args|
        guid, partial, _ = args

        x = fake.new(guid, self, nil, partial)

        # when creating an object, automatically set the org/space
        unless guid
          if klass.scoped_organization && current_organization
            x.send(:"#{klass.scoped_organization}=", current_organization)
          end

          if klass.scoped_space && current_space
            x.send(:"#{klass.scoped_space}=", current_space)
          end
        end

        x
      end
    end
  end
end
