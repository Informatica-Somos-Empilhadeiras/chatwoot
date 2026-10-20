# OUTSIDER: auditoria de uma oportunidade (ver app/services/outsider/crm/audit_trail.rb).
class Api::V1::Accounts::Outsider::Crm::OpportunityAuditsController < Api::V1::Accounts::Outsider::Crm::OpportunityChildController
  LIMIT = 200

  def index
    render json: ::Outsider::Crm::AuditTrail.new(@opportunity).to_a(limit: LIMIT)
  end
end
