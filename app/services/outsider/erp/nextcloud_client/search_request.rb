# OUTSIDER: o método SEARCH do WebDAV, que o Net::HTTP não traz (Outsider::Erp::NextcloudClient)
class Outsider::Erp::NextcloudClient::SearchRequest < Net::HTTPRequest
  METHOD = 'SEARCH'.freeze
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end
