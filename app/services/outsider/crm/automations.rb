# OUTSIDER: automações do CRM ao ganhar ou perder um negócio, ligadas por conta em Configurações >
# Automações (todas começam desligadas):
# - aplicar uma etiqueta do Chatwoot na conversa ligada ao negócio (uma para ganho, outra para perda);
# - concluir as tarefas pendentes do negócio.
# Cada ação fica na linha do tempo do negócio como "automação". A etiqueta entra como "Sistema de
# Automação", igual às automações do próprio Chatwoot. Nada é enviado ao cliente. Um erro aqui não
# desfaz o ganho ou a perda: vai para o log.
class Outsider::Crm::Automations
  # Roda como sistema: Current.user vazio faz o Chatwoot e a linha do tempo mostrarem "Sistema"
  def self.as_system(executed_by)
    previous = [Current.user, Current.executed_by]
    Current.user = nil
    Current.executed_by = executed_by
    yield
  ensure
    Current.user, Current.executed_by = previous
  end

  def self.log(opportunity, rule, **metadata)
    opportunity.activities.create!(account_id: opportunity.account_id, kind: :automation, metadata: metadata.merge(rule: rule).compact)
  end

  def initialize(opportunity)
    @opportunity = opportunity
    @settings = Outsider::Crm::Settings.new(opportunity.account)
  end

  def closed
    return unless @opportunity.won? || @opportunity.lost?

    apply_label(@settings["automation_#{@opportunity.status}_label"])
    close_tasks if @settings[:automation_close_tasks]
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @opportunity.account).capture_exception
  end

  private

  def apply_label(title)
    conversation = @opportunity.conversation
    return if title.blank? || conversation.nil? || conversation.label_list.include?(title)
    # etiqueta apagada no Chatwoot depois de escolhida: não recria, só registra
    return log("#{@opportunity.status}_label", label: title, missing: true) unless @opportunity.account.labels.exists?(title: title)

    self.class.as_system(@opportunity) { conversation.add_labels([title]) }
    log("#{@opportunity.status}_label", label: title, conversation_display_id: conversation.display_id)
  end

  def close_tasks
    tasks = @opportunity.tasks.pending.to_a
    return if tasks.empty?

    self.class.as_system(@opportunity) { tasks.each { |task| task.complete!(nil) } }
    log('close_tasks', count: tasks.size)
  end

  def log(rule, **metadata)
    self.class.log(@opportunity, rule, **metadata)
  end
end
