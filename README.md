# Gestão operacional do 4º Pelotão

Interface estática para GitHub Pages, com autenticação individual pelo Supabase Auth e banco PostgreSQL protegido no Supabase. A identidade visual utiliza o brasão fornecido pelo pelotão.

## Execução

Node.js 22 ou superior. Execute `npm ci`, `npm run build` e `npm run dev` para desenvolvimento. O caminho de publicação padrão é `/gestao-4-pelotao/`.

O arquivo `public/config.json` contém exclusivamente a URL do projeto Supabase e sua chave **publishable/anon**, própria para clientes públicos. Nunca inclua chave secreta, `service_role`, senha de banco ou tokens administrativos neste repositório.

## Banco e autenticação

1. Aplique a migração de estrutura em `supabase/migrations` a um projeto Supabase gratuito.
2. Importe os dados institucionais diretamente no banco por um canal administrativo autorizado. Não publique nomes, matrículas, números de série, inventários, históricos ou e-mails aqui.
3. Configure `private.settings.owner_email` com o e-mail do gestor autorizado. Este dado não fica no código da interface.
4. Publique a Edge Function `platform`. O gateway usa `verify_jwt=false` porque a função verifica explicitamente cada token com **Supabase Auth `getUser`**, exige e-mail confirmado e aplica autorização antes de consultar o banco. Isso permite os formatos atuais de tokens do Supabase sem aceitar requisições anônimas.
5. Configure a URL do site e as URLs permitidas de confirmação/recuperação no Supabase Auth para a URL publicada em GitHub Pages. Mantenha a confirmação de e-mail habilitada e senha mínima de 12 caracteres.
6. Preencha `public/config.json` com a URL e a chave pública verificadas do projeto.

As tabelas estão no schema `private`, com RLS habilitada e sem concessão de leitura/escrita para `anon` ou `authenticated`. A Edge Function usa a conexão de banco fornecida exclusivamente no servidor e restringe cada operação ao perfil autenticado. O administrador inicial é determinado por um e-mail previamente autorizado, nunca pelo primeiro visitante público. Não há senhas compartilhadas nem dados operacionais incorporados ao código público.

O acesso administrativo utiliza o login **4º Pelotão**, sem e-mail pessoal. Internamente, o Supabase Auth mantém uma identidade técnica no domínio reservado `accounts.invalid`, sem envio de mensagens. A primeira senha é definida pelo responsável em um link privado, válido por 45 minutos e utilizável uma única vez. O servidor compara o hash de um token aleatório de 256 bits armazenado no schema privado antes de criar a conta; a chave administrativa permanece exclusivamente no servidor. O link e a senha nunca devem entrar no repositório. A recuperação desse acesso institucional exige um procedimento administrativo no Supabase, pois não há caixa de e-mail associada. Os policiais mantêm contas individuais autorizadas pelo comando.

## Publicação

Em Settings → Pages do repositório, selecione GitHub Actions. O workflow compila a interface e publica a pasta `dist`. Novos commits em `main` atualizam a interface automaticamente.

O plano gratuito do Supabase pode pausar projetos com baixa atividade por sete dias e possui limites de uso. Não há serviço Render ou recurso pago neste projeto. O funcionamento completo depende de configurar e verificar o projeto Supabase: publicar a interface sozinha não ativa login ou banco.

## Funcionalidades

Conferências de serviço com rascunho e revisão, justificativas obrigatórias, inventário por município, cautelas individuais e por lote, recebimento/devolução, ocorrências com providências, auditoria e relatórios PDF/Excel. Os materiais e cadastros são carregados do banco somente após autenticação e autorização.
