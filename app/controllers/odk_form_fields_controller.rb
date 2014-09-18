class OdkFormFieldsController < ApplicationController
  def index
    odk = OdkAggregate::Connection.new(current_user.odk_url,
                                       current_user.odk_username,
                                       current_user.odk_password)
    odk_form_fields = odk.find_form(params[:odk_form_id]).fields.
      collect do |f|
        index = f["nodeset"].index("/", 1)
        {field_name: f["nodeset"][index..-1], field_type: f["type"], salesforceFields: []}
      end

    render json: odk_form_fields, root: false
  end
end
