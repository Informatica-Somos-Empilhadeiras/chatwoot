# OUTSIDER: em qual banco fica o cadastro de máquinas de cada unidade. No Mais Prático da Somos a tabela equipamentos só
# é tabela de verdade na matriz (somosemp) e em somosgo; nas outras unidades ela é uma VIEW do cadastro de outro banco
# (descoberta de 25/11/2026). Então a mesma máquina aparece em várias unidades e as OS e os contratos dela podem estar em
# qualquer uma das que enxergam o mesmo cadastro. Aqui:
# - bases: as unidades com cadastro próprio (a lista de máquinas lê só delas, sem repetir máquina);
# - base(unidade): o banco do cadastro que a unidade enxerga (pela definição da VIEW; sem ela, a primeira base);
# - members(base): as unidades que enxergam aquele cadastro (onde procurar OS e contratos da máquina).
# Lido do information_schema e guardado no Redis por um dia.
class Outsider::Erp::Rentals::Fleet
  S = Outsider::Erp::Sql
  TTL = 1.day

  def initialize(account, client:)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = client
  end

  def bases = map.select { |company, base| company == base }.keys

  def base(company) = map.fetch(company.to_s) { raise ArgumentError, 'empresa' }

  def members(base) = map.select { |_company, value| value == base }.keys

  private

  def map
    @map ||= cached { read }
  end

  def read
    companies = @settings.companies
    return {} if companies.empty?

    list = companies.map { |company| S.str(company) }.join(', ')
    types = rows("SELECT TABLE_SCHEMA AS banco, TABLE_TYPE AS tipo FROM information_schema.TABLES WHERE TABLE_NAME = 'equipamentos' " \
                 "AND TABLE_SCHEMA IN (#{list})").to_h { |row| [row['banco'].to_s, row['tipo'].to_s] }
    views = rows('SELECT TABLE_SCHEMA AS banco, VIEW_DEFINITION AS definicao FROM information_schema.VIEWS ' \
                 "WHERE TABLE_NAME = 'equipamentos' AND TABLE_SCHEMA IN (#{list})").to_h { |row| [row['banco'].to_s, row['definicao'].to_s] }
    resolve(companies.select { |company| types.key?(company) }, types, views)
  end

  def resolve(companies, types, views)
    bases = companies.select { |company| types[company].include?('BASE') }
    companies.to_h do |company|
      next [company, company] if bases.include?(company)

      target = views[company].to_s.scan(/`?(\w+)`?\.`?equipamentos`?/i).flatten.find { |name| bases.include?(name) }
      [company, target || bases.first || company]
    end
  end

  def rows(sql) = @client.query_execute(sql).grep(Hash)

  def cached
    key = "outsider_erp:#{@account.id}:fleet:#{@settings.companies.join(',')}"
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw) if raw

    value = yield
    Redis::Alfred.set(key, value.to_json, ex: TTL.to_i) if value.any?
    value
  end
end
