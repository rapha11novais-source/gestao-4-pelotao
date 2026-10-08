# Gestão operacional do 4º Pelotão

Interface estática para GitHub Pages, com autenticação individual pelo Supabase Auth e banco PostgreSQL protegido no Supabase. A identidade visual utiliza o brasão fornecido pelo pelotão.

## Execução

Node.js 22 ou superior. Execute `npm ci`, `npm run build` e `npm run dev` para desenvolvimento. O caminho de publicação padrão é `/gestao-4-pelotao/`.

O arquivo `public/config.json` contém exclusivamente a URL do projeto Supabase e sua chave **publishable/anon**, própria para clientes públicos. Nunca inclua chave secreta, `service_role`, senha de banco ou tokens administrativos neste repositório.

## Banco e autenticação

1. Aplique, em ordem, as migrações de estrutura em `supabase/migrations` a um projeto Supabase gratuito.
2. Importe os dados institucionais diretamente no banco por um canal administrativo autorizado. Não publique nomes, matrículas, números de série, inventários, históricos ou e-mails aqui.
3. Configure `private.settings.owner_email` com a identidade técnica do gestor autorizado. Este dado não fica no código da interface.
4. Publique a Edge Function `platform`. O gateway usa `verify_jwt=false` porque a função verifica explicitamente cada token com **Supabase Auth `getUser`**, exige e-mail confirmado e aplica autorização antes de consultar o banco. Isso permite os formatos atuais de tokens do Supabase sem aceitar requisições anônimas.
5. Configure a URL do site e as URLs permitidas de confirmação/recuperação no Supabase Auth para a URL publicada em GitHub Pages. Mantenha a confirmação de e-mail habilitada e senha mínima de 12 caracteres.
6. Preencha `public/config.json` com a URL e a chave pública verificadas do projeto.

As tabelas estão no schema `private`, com RLS habilitada e sem concessão de leitura/escrita para `anon` ou `authenticated`. A Edge Function usa a conexão de banco fornecida exclusivamente no servidor e restringe cada operação ao perfil autenticado. O administrador inicial é determinado por um e-mail previamente autorizado, nunca pelo primeiro visitante público. Não há senhas compartilhadas nem dados operacionais incorporados ao código público.

O acesso administrativo utiliza o login **4º Pelotão**, sem e-mail pessoal. Internamente, o Supabase Auth mantém uma identidade técnica no domínio reservado `accounts.invalid`, sem envio de mensagens. A primeira senha é definida pelo responsável com um código privado, válido por 45 minutos e utilizável uma única vez. O servidor compara o hash de um token aleatório de 256 bits armazenado no schema privado antes de criar a conta; a chave administrativa permanece exclusivamente no servidor. O código e a senha nunca devem entrar no repositório nem no endereço do navegador. A recuperação desse acesso institucional exige um procedimento administrativo no Supabase, pois não há caixa de e-mail associada. O gestor cria ou redefine as senhas em **Efetivo e acessos**, após validar o cadastro. Cada policial entra com sua matrícula; as identidades internas usam o domínio reservado `accounts.invalid`, sem necessidade de e-mail pessoal. Desative o cadastro público em Supabase Auth → Sign In / Providers → Allow new users to sign up. A criação das contas ocorre exclusivamente na função autenticada de gestão. As senhas nunca são registradas em auditoria.

## Publicação

Em Settings → Pages do repositório, selecione GitHub Actions. O workflow compila a interface e publica a pasta `dist`. Novos commits em `main` atualizam a interface automaticamente.

O plano gratuito do Supabase pode pausar projetos com baixa atividade por sete dias e possui limites de uso. Não há serviço Render ou recurso pago neste projeto. O funcionamento completo depende de configurar e verificar o projeto Supabase: publicar a interface sozinha não ativa login ou banco.

## Funcionalidades

Conferências de serviço com rascunho e revisão, justificativas obrigatórias, inventário por município, cautelas individuais e por lote, recebimento/devolução, ocorrências com providências, auditoria e relatórios PDF/Excel. Os materiais e cadastros são carregados do banco somente após autenticação e autorização.

## Conferência e carga individual

O comandante da guarnição registra uma conferência por município/dia, incluindo os nomes completos dos policiais. A data e o horário são obtidos no servidor, considerando o dia de Brasília, sem horário obrigatório. Há também limite de uma conferência por policial/dia. A seleção da guarnição permite pesquisa pela primeira letra, matrícula e navegação com as setas do teclado.

Depois da conferência, cada integrante registra uma carga por policial/dia. A quantidade disponível considera o estoque, o total encontrado na conferência, as outras cargas e as cautelas ativas. Transações e bloqueios das linhas de estoque impedem retiradas simultâneas acima do disponível. Os materiais permanecem reservados até a confirmação da devolução física. Devolver uma carga não permite criar outra no mesmo dia.

O PDF diário contém somente os materiais da carga individual, com identidade do policial, município, dia, horário e referência à conferência. O servidor autoriza o policial a acessar seus próprios relatórios e o comando a fiscalizar os registros gerais. O histórico continua disponível após a devolução.

Somente o perfil de comando pode excluir conferências, com motivo obrigatório e após a devolução das cargas vinculadas. A exclusão retira o registro das conferências ativas e preserva os dados e a auditoria. O PDF de uma carga devolvida indica eventual exclusão posterior da conferência.

## Administração delegada

Os perfis de administrador e comando têm os mesmos recursos de gestão, incluindo criação de usuários e senhas, exclusão de conferências, exclusão de usuários e concessão de perfis administrativos. Em Efetivo e acessos, use Tornar administrador ou edite o perfil de acesso do cadastro.

A conta institucional 4º Pelotão é identificada pelo ID de autenticação armazenado exclusivamente em private.settings.owner_user_id. A API e os gatilhos do banco impedem excluir ou retirar os privilégios desse perfil. O nome exibido ou parâmetros enviados pela interface não determinam quem é o gestor principal.

A exclusão de usuários bloqueia imediatamente novas operações mesmo com uma sessão existente, remove o cadastro da lista ativa e preserva histórico, matrícula e auditoria. Antes de excluir, devolva as cargas e cautelas abertas. Usuários excluídos podem ser consultados e restaurados; a restauração exige posterior validação e ativação do cadastro para retomar o acesso.
