# OUTSIDER: o nome de cada unidade (banco do ERP) como aparece nas telas, para ninguém precisar saber que "somosfilial" é
# a filial do Distrito Federal. Editável nas Configurações do ERP; unidade sem nome aparece pelo banco. Parte do
# Outsider::Erp::Settings.
module Outsider::Erp::Settings::CompanyNames
  COMPANY_NAMES_DEFAULTS = {
    'company_names' => {
      'somosemp' => 'Matriz', 'somosfilial' => 'Filial Distrito Federal', 'somosba' => 'Filial Bahia',
      'somosto' => 'Filial Tocantins', 'somosnordeste' => 'Somos Nordeste', 'somosgo' => 'Somos Empreendimentos'
    }
  }.freeze
  MAX_COMPANY_NAME = 60

  def company_names = data['company_names'].to_h

  private

  # { banco => nome }: só texto curto; nome vazio tira a unidade da lista (volta a aparecer pelo banco)
  def clean_company_names(params)
    names = params.fetch('company_names', company_names)
    return { 'company_names' => company_names } unless names.is_a?(Hash)

    cleaned = names.to_h { |db, name| [db.to_s.strip.downcase, name.to_s.squish.first(MAX_COMPANY_NAME)] }
    { 'company_names' => cleaned.select { |db, name| db.match?(Outsider::Erp::Settings::COMPANY) && name.present? } }
  end
end
