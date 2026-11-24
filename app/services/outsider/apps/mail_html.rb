# OUTSIDER: o corpo dos e-mails dos aplicativos (Outlook e Gmail).
#   clean: e-mail recebido, que a tela mostra num iframe isolado (sandbox, sem scripts). Mesmo assim tira script, iframe,
#     formulários e atributos on*, faz os links abrirem em outra aba e troca as imagens coladas (cid:) pelo endereço
#     assinado do anexo. Corta em 1,5 MB (e-mail gigante de propaganda).
#   outgoing: o texto que a pessoa escreveu no Chatwoot (texto simples) vira HTML seguro, com as quebras de linha.
module Outsider::Apps::MailHtml
  MAX = 1_500_000
  REMOVE = 'script, iframe, frame, frameset, object, embed, applet, form, input, button, textarea, select, meta[http-equiv], base'.freeze

  module_function

  def clean(html, inline = {})
    doc = Nokogiri::HTML(html.to_s.first(MAX))
    doc.css(REMOVE).each(&:remove)
    doc.traverse do |node|
      next unless node.element?

      node.attribute_nodes.each do |attribute|
        name = attribute.name.downcase
        value = attribute.value.to_s.strip
        attribute.remove if name.start_with?('on') || (%w[href src action
                                                          formaction].include?(name) && value.match?(/\A\s*(javascript|vbscript|data:text)/i))
      end
      replace_cid(node, inline) if node.name == 'img'
      if node.name == 'a'
        node['target'] = '_blank'
        node['rel'] = 'noopener noreferrer'
      end
    end
    head = doc.at('head') || doc.root&.add_child(Nokogiri::XML::Node.new('head', doc))
    head&.prepend_child('<base target="_blank"><meta name="referrer" content="no-referrer">')
    doc.to_html
  end

  def replace_cid(node, inline)
    src = node['src'].to_s
    return unless src.downcase.start_with?('cid:')

    cid = src.sub(/\Acid:/i, '').split('@').first.to_s.downcase
    url = inline[cid] || inline.find { |name, _| name.start_with?(cid) || cid.start_with?(File.basename(name, '.*')) }&.last
    url ? node['src'] = url : node.remove
  end

  def outgoing(text)
    escaped = ERB::Util.html_escape(text.to_s.first(100_000)).to_s.gsub(/\r?\n/, '<br>')
    "<div style=\"font-family:Calibri,Arial,sans-serif;font-size:11pt\">#{escaped}</div>"
  end
end
