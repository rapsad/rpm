# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    module Datastores

      # Add Datastore tracing to a method. This properly generates the
      # metrics for New Relic's Datastore features.
      #
      # +clazz+ the class to instrument
      #
      # +method_name+ string or symbol with name of instance method to
      # instrument
      #
      # +product+ name of your datastore for use in metric naming, e.g. "Redis"
      #
      # +operation+ optional name of operation to apply if different than the
      # instrumented method name
      #
      # @api public
      #
      def self.trace(clazz, method_name, product, operation = method_name)
        clazz.class_eval do
          method_name_without_newrelic = "#{method_name}_without_newrelic"

          if NewRelic::Helper.instance_methods_include?(clazz, method_name) &&
             !NewRelic::Helper.instance_methods_include?(clazz, method_name_without_newrelic)

            visibility = NewRelic::Helper.instance_method_visibility(clazz, method_name)

            alias_method method_name_without_newrelic, method_name

            define_method(method_name) do |*args, &blk|
              metrics = MetricHelper.metrics_for(product, operation)
              NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
                send(method_name_without_newrelic, *args, &blk)
              end
            end

            send visibility, method_name
            send visibility, method_name_without_newrelic
          end
        end
      end

      # Wrap a call to a datastore and record New Relic Datastore metrics. This
      # method can be used when a collection (i.e. table or model name) is
      # known at runtime to be included in the metric naming. It is intended
      # for situations that the simpler NewRelic::Agent::Datastores.trace can't
      # properly handle.
      #
      # To use this, wrap the datastore operation in the block passed to wrap.
      #
      #   NewRelic::Agent::Datastores.wrap("FauxDB", "find", "items") do
      #     FauxDB.find(query)
      #   end
      #
      # +product+ datastore name for use in metric naming, e.g. "FauxDB"
      #
      # +operation+ name of operation, often named after the method that's
      # being instrumented.
      #
      # +collection+ optional collection name to include. Will result in
      # statement-level metrics (i.e. table or model name)
      #
      # +notice+ proc or other callable to invoke after running the datastore
      # block. Receives three arguments: result of the yield, list of metric
      # names, and elapsed call time call.
      #
      # @api public
      #
      def self.wrap(product, operation, collection = nil, notice = nil)
        return yield unless operation

        metrics = MetricHelper.metrics_for(product, operation, collection)
        NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
          t0 = Time.now
          begin
            result = yield
          ensure
            if notice
              elapsed_time = (Time.now - t0).to_f
              notice.call(result, metrics, elapsed_time)
            end
          end
        end
      end

    end
  end
end
