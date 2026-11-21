# OUTSIDER: o método SEARCH do WebDAV, que o Net::HTTP não traz (Outsider::Erp::NextcloudInvoices)
class Outsider::Erp::NextcloudInvoices::SearchRequest < Net::HTTPRequest
  METHOD = 'SEARCH'.freeze
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end
