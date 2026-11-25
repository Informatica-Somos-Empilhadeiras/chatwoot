# OUTSIDER: OS do ERP feita no chat (Outsider::Erp::Orders::Creator): a Nova OS ou a conversão de um orçamento do ERP.
# Rascunho -> "Gravar no ERP" (status submitting, Outsider::Erp::OrderSubmitJob) -> created, com o número oficial da OS.
# A OS leva MARKER + id no campo "código em outro sistema" do Mais Prático (CodigoPedidoOutroSistema): é por ele que uma
# gravação que caiu no meio acha a OS e continua, sem criar outra.
#
# fields: maquina, serie, maquina_descricao, maquina_do_cliente, horimetro, tipo_atendimento, tecnico, tecnico_nome,
# previsao (AAAA-MM-DDTHH:MM), entrega (AAAA-MM-DD), classe, maquina_parada, defeitos, observacoes, agendar, enviar_app
# (ver Outsider::Erp::Orders::Form). items (só a Nova OS; a conversão leva os itens do próprio orçamento):
# [{ codigo, descricao, unidade, tipo, quantidade, preco }].
# erp_result: steps (o que já foi feito), checks (conferência antes de gravar), error, readback (lido de volta), cancelled_at.
class Outsider::Erp::OrderDraft < ApplicationRecord
  self.table_name = 'outsider_erp_order_drafts'
  MARKER = 'CHATWOOT-OS-'.freeze

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :user, optional: true

  enum :kind, { fresh: 0, conversion: 1 }, validate: true
  enum :status, { draft: 0, submitting: 1, created: 2 }, validate: true

  validates :company, presence: true, format: { with: Outsider::Erp::Sql::IDENT }
  validates :quote_number, presence: true, if: :conversion?
  validate :same_account

  def marker = "#{MARKER}#{id}"
  def in_erp? = erp_number.present?
  def steps = Array(erp_result.to_h['steps'])
  def step?(name) = steps.include?(name.to_s)
  def cancelled? = erp_result.to_h['cancelled_at'].present?

  def self.line_total(item) = (item['quantidade'].to_d * item['preco'].to_d).round(2)
  def total = items.sum { |item| self.class.line_total(item) }

  private

  def same_account
    errors.add(:contact, :invalid) if contact && contact.account_id != account_id
  end
end
