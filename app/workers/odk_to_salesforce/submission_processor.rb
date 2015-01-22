module OdkToSalesforce
  class SubmissionProcessor

    include Sidekiq::Worker

    def perform(mapping_id, submission_id)
      @mapping = Mapping.find(mapping_id)
      @submission = Submission.find(submission_id)
      @converter = OdkToSalesforce::Converter.new
      @restforce_connection = RestforceService.new(@mapping.user).connection

      @logger = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT)) 
      @logger.push_tags("SubmissionProcessor", "Submission##{@submission.id}", "Mapping##{@mapping.id}")

      @all_import_objects = []

      begin
        process_submission(@submission)
      rescue Exception => e

        @logger.error "An error occurred"
        @logger.error e.message
        NewRelic::Agent.notice_error(e, mapping_id: @mapping.id, submission_id: @submission.id)

        # => Destroy all objects that were created before this error
        # => If the record already existed before this import, leave it!
        @all_import_objects.each do |io|
          puts "Deleting #{io.object_name}: #{io.id}"
          io.destroy if io.new_record
        end

        @submission.message = e.message
        @submission.backtrace = e.backtrace.first(15).join('<br />')
        @submission.failed
      end
    end

    protected

    def process_submission(submission)

      @logger.info "Starting"

      # => Mark this submission as being processed, for the first time or
      submission.process

      salesforce_objects = @mapping.salesforce_objects

      # => Loop through each SalesforceObject in the mapping
      salesforce_objects.each do |salesforce_object|

        # => Load the fields for the salesforce_object
        @converter.odk_data(salesforce_object, submission.data).each_with_index do |odk_data, i|
          # Skip any potential nil records, even if they have an instanceID
          # We work this out on the basis that all the values are nil
          # and the only other value is a hash (meta: {instanceID: '123'})
          if odk_data.except("meta").values.all?(&:nil?)
            @logger.info "Skipping #{salesforce_object.name} creation, all values are `nil`."
            next
          end

          create_in_salesforce(salesforce_object, odk_data, i)
        end
      end

      submission.successful
    end

    def create_in_salesforce(salesforce_object, submission_data, index)
      salesforce_fields = salesforce_object.salesforce_fields.joins(:odk_fields)

      import_object = OdkToSalesforce::SalesforceObjects::ImportObject.new(@restforce_connection, salesforce_object)

      salesforce_fields.each do |salesforce_field|

        # => TODO: concatenate multiple fields
        odk_field = salesforce_field.odk_fields.first

        odk_field_value = @converter.get_field_content(odk_field, submission_data)
        odk_field_value = transform_uuid_value(odk_field_value, salesforce_object, index) if odk_field.is_uuid

        case salesforce_field.data_type
        when "reference"
          # => This is a lookup field
          import_object.populate_lookup_field(salesforce_field, odk_field_value)
        when "record_type_id"
          import_object.populate_record_type_field(salesforce_field, odk_field_value)
        when "boolean"
          import_object.attributes[salesforce_field.field_name] = odk_field_value.to_bool
        else
          # => Process the regular field
          import_object.attributes[salesforce_field.field_name] = odk_field_value
        end
      end

      import_object.populate_relationships(@all_import_objects)

      if import_object.save
        @all_import_objects << import_object
      end
    end

    def transform_uuid_value(uuid, salesforce_object, index)
      if salesforce_object.is_repeat
        return "#{uuid}/#{salesforce_object.order}r/#{index + 1}"
      else
        return "#{uuid}/#{salesforce_object.order}"
      end
    end
  end
end
