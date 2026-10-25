import { parseOperatorText } from '../operatorText';
import { stateForNumber } from '../brazil';

describe('parseOperatorText', () => {
  it('reads a Portuguese e-mail from the operator', () => {
    const result = parseOperatorText(`
      Olá! Seguem os dados do seu tronco SIP:
      Domínio/Proxy: sip:sip.operadora.com.br:5080
      Usuário: 1130041234
      Usuário de autenticação: 99887766
      Senha: Ab12#x:yz
      Protocolo: UDP
      IP de sinalização: 200.150.10.20 e 200.150.10.21
      Números (DID): (62) 3234-5678, +55 11 3234-5678
    `);

    expect(result.trunk).toEqual({
      host: 'sip.operadora.com.br',
      port: 5080,
      username: '1130041234',
      auth_username: '99887766',
      password: 'Ab12#x:yz',
      transport: 'udp',
      ips: ['200.150.10.20', '200.150.10.21'],
      auth: 'register',
    });
    expect(result.numbers).toEqual(['6232345678', '1132345678']);
  });

  it('reads English labels, IP authentication and the username as the number', () => {
    const ip = parseOperatorText(
      'SIP Server: 189.20.30.40\nTransport: TCP\nPort: 5060\nAllowed IPs: 189.20.30.40'
    );
    expect(ip.trunk).toMatchObject({
      host: '189.20.30.40',
      transport: 'tcp',
      port: 5060,
      auth: 'ip',
    });

    const user = parseOperatorText(
      'Login: 556232345678\nPassword: segredo\nRegistrar: vox.example.com'
    );
    expect(user.numbers).toEqual(['6232345678']);
  });

  it('suggests the state from the area code', () => {
    expect(stateForNumber('(62) 3234-5678')).toBe('GO');
    expect(stateForNumber('+55 11 99999-8888')).toBe('SP');
    expect(stateForNumber('190')).toBe('');
  });
});
