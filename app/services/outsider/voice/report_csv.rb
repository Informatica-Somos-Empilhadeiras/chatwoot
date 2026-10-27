require 'csv'

# OUTSIDER: planilhas da Telefonia (Entrega 24), em CSV com ";" para abrir direto no Excel em pt-BR:
# - calls: uma linha por ligação (do painel, no período, ou de Ligações, com os filtros da tela);
# - agents: os números de cada vendedor no período;
# - days: os números dia a dia (ou mês a mês, em período longo).
# Datas e horas no fuso da telefonia.
class Outsider::Voice::ReportCsv
  LIMIT = 20_000
  KINDS = %w[calls agents days].freeze
  DIRECTIONS = { 'inbound' => 'recebida', 'outbound' => 'feita', 'internal' => 'entre ramais' }.freeze
  STATUS = { 'ringing' => 'em andamento', 'answered' => 'atendida', 'missed' => 'perdida', 'unanswered' => 'não atendeu',
             'busy' => 'ocupado', 'failed' => 'falhou' }.freeze
  CALL_HEADERS = %w[data hora tipo situacao vendedor cliente numero_cliente numero_empresa estado espera_seg duracao duracao_seg
                    retornada_em retornada_por negocio gravacao].freeze
  AGENT_HEADERS = %w[vendedor ramal ligacoes feitas atendidas_pelo_cliente taxa_contato recebidas_atendidas entre_ramais
                     minutos_em_ligacao tempo_medio_conversa clientes].freeze
  DAY_HEADERS = %w[periodo ligacoes recebidas_atendidas perdidas feitas entre_ramais minutos_em_ligacao taxa_atendimento].freeze

  def initialize(zone)
    @zone = zone
  end

  def calls(scope)
    generate(CALL_HEADERS) do |csv|
      scope.includes(:user, :contact, :returned_by, recording_attachment: :blob).limit(LIMIT).each { |call| csv << call_row(call) }
    end
  end

  def agents(rows)
    generate(AGENT_HEADERS) do |csv|
      rows.each do |row|
        csv << [row[:name], row[:extension], row[:total], row[:outbound], row[:outbound_answered], percent(row[:contact_rate]),
                row[:inbound_answered], row[:internal], minutes(row[:talk_seconds]), duration(row[:average_talk]), row[:customers]]
      end
    end
  end

  def days(timeline)
    generate(DAY_HEADERS) do |csv|
      Array(timeline&.dig(:rows)).each do |row|
        label = timeline[:unit] == 'month' ? row[:date].strftime('%m/%Y') : row[:date].strftime('%d/%m/%Y')
        csv << [label, row[:total], row[:inbound_answered], row[:missed], row[:outbound], row[:internal], minutes(row[:talk_seconds]),
                percent(row[:answer_rate])]
      end
    end
  end

  private

  def generate(headers)
    "﻿#{CSV.generate(col_sep: ';') do |csv|
      csv << headers
      yield csv
    end}"
  end

  def call_row(call)
    started = call.started_at.in_time_zone(@zone)
    [
      started.strftime('%d/%m/%Y'), started.strftime('%H:%M:%S'), DIRECTIONS[call.direction], STATUS[call.status], call.user&.name,
      call.contact&.name, call.customer_number, call.did, call.state_code, wait(call), duration(call.talk_seconds), call.talk_seconds
    ] + return_columns(call) + [call.opportunity_id, call.recording.attached? ? 'sim' : nil]
  end

  # recebida atendida: quanto tempo tocou até alguém atender
  def wait(call)
    (call.answered_at - call.started_at).round if call.inbound? && call.answered_at
  end

  def return_columns(call)
    [call.returned_at&.in_time_zone(@zone)&.strftime('%d/%m/%Y %H:%M'), call.returned_by&.name]
  end

  def duration(seconds)
    seconds = seconds.to_i
    format('%<h>d:%<m>02d:%<s>02d', h: seconds / 3600, m: (seconds % 3600) / 60, s: seconds % 60)
  end

  def minutes(seconds)
    format('%.1f', seconds.to_i / 60.0).tr('.', ',')
  end

  def percent(value)
    value.nil? ? '' : "#{format('%.1f', value).tr('.', ',')}%"
  end
end
