#designsketch

# only for PUSH destination integrations. Pulls can be handled by storing destination payloads for collection.

class Submission::Dispatch

  include Sidekiq::Worker
  
  def perform(submission)
    integration_klass.submit!(submission.raw_destination_payload, submission.integration.destination_credentials)
    submission.submitted!
  end

  private
  def integration_klass
    Integration.const_get(submission.integration.destination.integration_type)
  end
end
