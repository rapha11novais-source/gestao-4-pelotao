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

Uma conferência inicial por serviço e uma cautela por integrante em cada serviço, inclusive pelo comandante. Serviços de 8, 24, 48, 72 ou 96 horas usam o início efetivo informado pelo responsável e calculam o encerramento previsto. As operações têm data/hora de registro no servidor e apresentação no horário de Brasília. Não existe encerramento automático por horário ou mudança de dia.

As cargas usam o menor valor entre o estoque patrimonial e a quantidade encontrada, descontando cargas e cautelas ativas. Bloqueios de linha e transações evitam duplicidade e excesso de retirada. O estoque permanece reservado até a devolução física. Relatórios PDF/Excel respeitam o escopo; o PDF individual identifica a carga, o policial, a matrícula, o município e o pelotão.

Exclusões de materiais, usuários e conferências são lógicas, justificadas e auditadas. Cargas e cautelas ativas devem ser devolvidas antes da exclusão. Retificações são acrescentadas ao histórico e aos relatórios; não substituem a conferência finalizada original. A auditoria registra nome, matrícula, município, pelotão, horário e dados anteriores/novos.

## Serviço ativo e passagem de responsabilidade

Cada DPM mantém no máximo um serviço aberto, incluindo a conferência em rascunho. A finalização da conferência libera a cautela somente aos integrantes cadastrados. O encerramento individual confirma cada equipamento, o armamento e as munições; o comandante da guarnição também pode realizar a conferência final e o encerramento coletivo em uma única operação, revisando cada integrante, seus armamentos, munições e quantidades efetivamente devolvidas. Encerramentos individuais anteriores permanecem imutáveis. A unidade é liberada para o próximo serviço somente após essa confirmação geral. O comandante do próprio pelotão e o gestor geral podem realizar encerramentos administrativos individuais ou coletivos, com justificativa e auditoria. Ausências, avarias, devoluções parciais, ausência de cautela inicial e cautelas formais ainda ativas exigem registro explícito; nenhuma devolução é presumida. Cautelas formais recebidas no próprio DPM de origem podem ser devolvidas com confirmação física na mesma operação. Movimentações entre unidades permanecem ativas até regularização formal. A operação coletiva é transacional: qualquer falha impede o encerramento parcial da equipe.

Equipamentos não devolvidos permanecem reservados mesmo depois do encerramento. Devoluções complementares e transferências formais acrescentam eventos, mantendo o recebimento e o encerramento originais. Avarias e divergências geram pendências para o comando. Fotos e PDFs de conferência e encerramento usam o bucket privado `service-evidence`, com até 8 MB por arquivo, identificação do remetente e links autenticados de 60 segundos.

Cada policial deve confirmar uma pistola do DPM ou informar sua pistola institucional de carga fixa. O cadastro permanente da carga fixa é reutilizado; uma substituição preserva o registro anterior e exige justificativa. Munições de carga fixa são declaradas separadamente das retiradas do DPM, inclusive com justificativa quando forem zero. O armamento permanente não integra o inventário do DPM e não exige devolução ao final do serviço. O PDF individual inclui armamento, munições, jornada e encerramento.

Os registros anteriores à implantação continuam intactos. A última conferência de cada unidade é apresentada como registro legado aguardando confirmação ou regularização, sem presumir jornada, devolução ou encerramento. As datas originais são identificadas como datas do registro, sem atribuir um início operacional não informado.

## Estrutura operacional expansível

Os pelotões, municípios e DPMs são carregados do banco em cada solicitação autenticada. O gestor geral cadastra e administra novas unidades pela interface, sem alteração do código ou duplicação de policiais. A identificação da unidade é estável para preservar os históricos; nome de apresentação, município e vinculação administrativa são registrados separadamente. Desativações e reorganizações exigem regularização dos serviços, cautelas, movimentações e custódias. Os registros não são excluídos.

A estrutura é mantida no contexto de cada solicitação do servidor, evitando mistura de unidades entre requisições concorrentes. Vínculos operacionais múltiplos não concedem administração. A retirada de um vínculo é bloqueada enquanto existir serviço ainda sob responsabilidade do policial.

## Veículos apreendidos e recolhidos

O módulo de custódia mantém registros independentes do encerramento do serviço. O comandante da guarnição inicia ou retoma sua conferência, vinculado à matrícula e ao DPM, para cadastrar veículos e registrar saídas. A conferência inclui automaticamente os veículos ativos; uma verificação pendente impede a finalização, e a não localização exige justificativa e gera alerta sem retirar o veículo da custódia. Os relatórios PDF e Excel preservam a situação verificada naquele serviço.

O cadastro compara características físicas e documentais sem concluir pela existência de adulteração. Possíveis duplicidades exigem comparação explícita dos registros ativos e justificativa auditada de que são veículos distintos. Retificações e observações acrescentam eventos, preservando os dados anteriores.

Somente uma saída formal, com confirmação da entrega física e destinação, encerra a custódia. A apresentação à Polícia Civil exige BO; outra destinação exige justificativa. A liberação depende de autorização registrada pelo comando do próprio pelotão ou gestor geral, vinculada ao veículo e à versão cadastral, consumida uma única vez. Uma retificação invalida autorizações da versão anterior.

As fotos e os documentos ficam no bucket privado `vehicle-custody`, com limite de 8 MB por arquivo e formatos validados no servidor. A função autenticada valida o município antes de emitir links de acesso de 60 segundos. Nome, matrícula, data, finalidade e hash do anexo são registrados; nenhuma fotografia ou relação de veículos entra no repositório público.

O comando acompanha alertas de conferência pendente, não localização, características divergentes, saída e permanência prolongada. O prazo de permanência é configurado por DPM, sem valor presumido. O trabalho `vehicle-custody-age-alerts` verifica os prazos a cada hora. A visualização e o tratamento dos alertas ficam no histórico da plataforma; não dependem de e-mail ou mensagens externas. Os novos dados usam o mesmo banco privado e preservam os cadastros anteriores.

## Senhas e segurança

O login pessoal é a matrícula, sem e-mail pessoal. O domínio reservado `accounts.invalid` fornece a identidade interna, sem envio de mensagens. A senha temporária usa PrimeiroNome.Matrícula, apenas por solicitação explícita do responsável. A troca por uma senha diferente, de no mínimo 12 caracteres, é obrigatória antes de acessar materiais ou realizar operações. As senhas não entram na auditoria.

A preparação das contas exige autorização privada aleatória de 256 bits, com validade curta, comparação por hash e utilização única. Uma retomada preserva contas já preparadas. O usuário administrativo 4º Pelotão mantém sua senha e identidade. Cadastros inativos, excluídos ou pendentes de validação não ganham acesso pelo fato de existir uma conta Auth.

As tabelas ficam no schema private, com RLS e permissões negadas a anon/authenticated. A função platform valida o token com Supabase Auth getUser e obtém vínculos/permissões do banco. O contexto autenticado também é transmitido às transações; gatilhos PostgreSQL validam escopo de escrita e imutabilidade do histórico. Operações entre pelotões e alterações de permissões exigem gestor geral.

O gateway platform usa verify_jwt=false porque a função implementa autenticação própria explícita e os procedimentos privados de configuração verificam seus tokens de autorização. As únicas origens da interface permitidas durante a migração são o site original e o endereço institucional. Mantenha cadastro público e login anônimo desativados no Supabase Auth. Configure Site URL e redirects para o endereço institucional, preservando o original como endereço autorizado durante a validação.

O plano é gratuito, sujeito aos limites e às regras de inatividade do GitHub Pages e do Supabase.

## Centro de operações

A Visão Geral é a página inicial de todos os perfis. Os indicadores de policiais em serviço, guarnições ativas, serviços encerrados e atenção necessária consideram somente os registros visíveis conforme o acesso. A equipe operacional pode consultar seus integrantes; armamentos, cautelas e observações individuais de outros policiais continuam restritos ao responsável e ao comando autorizado. O comando pode selecionar unidades, consultar pendências e iniciar os encerramentos no próprio painel. Conferências e cargas por período permanecem disponíveis em uma seção de consulta expansível.
