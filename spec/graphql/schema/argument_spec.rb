# frozen_string_literal: true
require "spec_helper"

describe GraphQL::Schema::Argument do
  module SchemaArgumentTest
    class Query < GraphQL::Schema::Object
      field :field, String, null: true do
        argument :arg, String, description: "test", required: false

        argument :arg_with_block, String, required: false do
          description "test"
        end

        argument :aliased_arg, String, required: false, as: :renamed
        argument :prepared_arg, Int, required: false, prepare: :multiply
        argument :prepared_by_proc_arg, Int, required: false, prepare: ->(val, context) { context[:multiply_by] * val }
        argument :exploding_prepared_arg, Int, required: false, prepare: ->(val, context) do
          raise GraphQL::ExecutionError.new('boom!')
        end

        argument :keys, [String], required: false

        class Multiply
          def call(val, context)
            context[:multiply_by] * val
          end
        end

        argument :prepared_by_callable_arg, Int, required: false, prepare: Multiply.new
      end

      def field(**args)
        args.inspect
      end

      def multiply(val)
        context[:multiply_by] * val
      end
    end

    class Schema < GraphQL::Schema
      query(Query)
      if TESTING_INTERPRETER
        use GraphQL::Execution::Interpreter
      end
    end
  end

  describe "#keys" do
    it "is not overwritten by the 'keys' argument" do
      expected_keys = ["aliasedArg", "arg", "argWithBlock", "explodingPreparedArg", "keys", "preparedArg", "preparedByCallableArg", "preparedByProcArg"]
      assert_equal expected_keys, SchemaArgumentTest::Query.fields["field"].arguments.keys.sort
    end
  end

  describe "#path" do
    it "includes type, field and argument names" do
      assert_equal "Query.field.argWithBlock", SchemaArgumentTest::Query.fields["field"].arguments["argWithBlock"].path
    end
  end

  describe "#name" do
    it "reflects camelization" do
      assert_equal "argWithBlock", SchemaArgumentTest::Query.fields["field"].arguments["argWithBlock"].name
    end
  end

  describe "#type" do
    let(:argument) { SchemaArgumentTest::Query.fields["field"].arguments["arg"] }
    it "returns the type" do
      assert_equal GraphQL::Types::String, argument.type
    end
  end

  describe "graphql definition" do
    it "calls block" do
      assert_equal "test", SchemaArgumentTest::Query.fields["field"].arguments["argWithBlock"].description
    end
  end

  describe "#description" do
    let(:arg) { SchemaArgumentTest::Query.fields["field"].arguments["arg"] }
    it "sets description" do
      arg.description "new description"
      assert_equal "new description", arg.description
    end

    it "returns description" do
      assert_equal "test", SchemaArgumentTest::Query.fields["field"].arguments["argWithBlock"].description
    end

    it "has an assignment method" do
      arg.description = "another new description"
      assert_equal "another new description", arg.description
    end
  end

  describe "as:" do
    it "uses that Symbol for Ruby kwargs" do
      query_str = <<-GRAPHQL
      { field(aliasedArg: "x") }
      GRAPHQL

      res = SchemaArgumentTest::Schema.execute(query_str)
      # Make sure it's getting the renamed symbol:
      assert_equal '{:renamed=>"x"}', res["data"]["field"]
    end
  end

  describe "prepare:" do
    it "calls the method on the field's owner" do
      query_str = <<-GRAPHQL
      { field(preparedArg: 5) }
      GRAPHQL

      res = SchemaArgumentTest::Schema.execute(query_str, context: {multiply_by: 3})
      # Make sure it's getting the renamed symbol:
      assert_equal '{:prepared_arg=>15}', res["data"]["field"]
    end

    it "calls the method on the provided Proc" do
      query_str = <<-GRAPHQL
      { field(preparedByProcArg: 5) }
      GRAPHQL

      res = SchemaArgumentTest::Schema.execute(query_str, context: {multiply_by: 3})
      # Make sure it's getting the renamed symbol:
      assert_equal '{:prepared_by_proc_arg=>15}', res["data"]["field"]
    end

    it "calls the method on the provided callable object" do
      query_str = <<-GRAPHQL
      { field(preparedByCallableArg: 5) }
      GRAPHQL

      res = SchemaArgumentTest::Schema.execute(query_str, context: {multiply_by: 3})
      # Make sure it's getting the renamed symbol:
      assert_equal '{:prepared_by_callable_arg=>15}', res["data"]["field"]
    end

    it "handles exceptions raised by prepare" do
      query_str = <<-GRAPHQL
        { f1: field(arg: "echo"), f2: field(explodingPreparedArg: 5) }
      GRAPHQL

      res = SchemaArgumentTest::Schema.execute(query_str, context: {multiply_by: 3})
      assert_equal({ 'f1' => '{:arg=>"echo"}', 'f2' => nil }, res['data'])
      assert_equal(res['errors'][0]['message'], 'boom!')
      assert_equal(res['errors'][0]['path'], ['f2'])
    end
  end
end
