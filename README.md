# Gestão de Pelotões · 80ª CIPM

Plataforma única para os 2º, 3º e 4º Pelotões, com interface estática no GitHub Pages, autenticação por matrícula no Supabase Auth e banco PostgreSQL privado. A cópia institucional usa o mesmo projeto Supabase; não duplica usuários ou inventários.

## Desenvolvimento e publicação

Use Node.js 24, `npm ci`, `npm run dev` e `npm run build`. O caminho padrão preserva `/gestao-4-pelotao/`; a publicação institucional define `VITE_BASE_PATH=/`. O workflow GitHub Actions publica a pasta `dist`.

`public/config.json` contém apenas a URL Supabase e sua chave pública publishable/anon. Nunca inclua senha, chave secreta, service_role, token temporário, relação nominal ou inventário no repositório. Importações, verificações com dados institucionais e códigos privados ficam em `.private/`, que é ignorado pelo Git.

## Estrutura e acessos

- 2º Pelotão: Ribeirão do Largo e Encruzilhada.
- 3º Pelotão: Belo Campo, Tremedal e Piripá.
- 4º Pelotão: Condeúba, Cordeiros e Mortugaba.

Somente a conta técnica principal 4º Pelotão e o cadastro designado em `private.settings.general_manager_officer_id` têm gestão geral. O identificador fixo da conta técnica é armazenado em `owner_user_id`; nomes exibidos e metadados editáveis do usuário não concedem privilégios.

Comandantes e administradores gerenciam o próprio pelotão e consultam indicadores dos demais. Subcomandantes consultam seu pelotão; o gestor geral pode conceder individualmente cadastro de materiais, gestão de policiais, movimentações, auditoria e consulta de status global. Policiais possuem acesso operacional pelos vínculos ativos em `officer_platoons`. Vínculos múltiplos não conferem administração.

Cadastros anteriores e registros do 4º são preservados. A relação nominal dos novos pelotões é importada por canal administrativo, deduplicada pela matrícula. Nomes extraídos de imagens devem ser validados antes de autorizar o acesso; não são incorporados aos arquivos públicos.

## Conferências, cargas e histórico

Uma conferência por município/dia, realizada pelo comandante da guarnição, e uma conferência por responsável/dia. Cada policial registra uma carga por dia. O dia é calculado em America/Sao_Paulo; a data e hora efetivas são registradas no servidor, sem horário obrigatório.

As cargas usam o menor valor entre o estoque patrimonial e a quantidade encontrada, descontando cargas e cautelas ativas. Bloqueios de linha e transações evitam duplicidade e excesso de retirada. O estoque permanece reservado até a devolução física. Relatórios PDF/Excel respeitam o escopo; o PDF individual identifica a carga, o policial, a matrícula, o município e o pelotão.

Exclusões de materiais, usuários e conferências são lógicas, justificadas e auditadas. Cargas e cautelas ativas devem ser devolvidas antes da exclusão. Retificações são acrescentadas ao histórico e aos relatórios; não substituem a conferência finalizada original. A auditoria registra nome, matrícula, município, pelotão, horário e dados anteriores/novos.

## Senhas e segurança

O login pessoal é a matrícula, sem e-mail pessoal. O domínio reservado `accounts.invalid` fornece a identidade interna, sem envio de mensagens. A senha temporária usa PrimeiroNome.Matrícula, apenas por solicitação explícita do responsável. A troca por uma senha diferente, de no mínimo 12 caracteres, é obrigatória antes de acessar materiais ou realizar operações. As senhas não entram na auditoria.

A preparação das contas exige autorização privada aleatória de 256 bits, com validade curta, comparação por hash e utilização única. Uma retomada preserva contas já preparadas. O usuário administrativo 4º Pelotão mantém sua senha e identidade. Cadastros inativos, excluídos ou pendentes de validação não ganham acesso pelo fato de existir uma conta Auth.

As tabelas ficam no schema private, com RLS e permissões negadas a anon/authenticated. A função platform valida o token com Supabase Auth getUser e obtém vínculos/permissões do banco. O contexto autenticado também é transmitido às transações; gatilhos PostgreSQL validam escopo de escrita e imutabilidade do histórico. Operações entre pelotões e alterações de permissões exigem gestor geral.

O gateway platform usa verify_jwt=false porque a função implementa autenticação própria explícita e os procedimentos privados de configuração verificam seus tokens de autorização. As únicas origens da interface permitidas durante a migração são o site original e o endereço institucional. Mantenha cadastro público e login anônimo desativados no Supabase Auth. Configure Site URL e redirects para o endereço institucional, preservando o original como endereço autorizado durante a validação.

O plano é gratuito, sujeito aos limites e às regras de inatividade do GitHub Pages e do Supabase.
