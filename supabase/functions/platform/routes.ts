import {actor,admin,stmt,db,UserError,textValue,integer,auditStmt,guard,clearGuard} from './server.ts';
import {CITIES,CONDITIONS,needsJustification,type Item,type Officer,type Entry} from './domain.ts';

const city=(v:unknown)=>{if(!CITIES.includes(v as any))throw new UserError('Selecione um município válido.');return String(v);};
const json=(v:unknown,status=200)=>Response.json(v,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
function error(e:unknown){console.error(e instanceof Error?e.message:e);if(e instanceof UserError)return json({error:e.message},e.status);const s=String(e);if(s.includes('operation_valid'))return json({error:'O registro foi alterado por outro usuário. Atualize os dados e revise novamente.'},409);if(s.includes('UNIQUE')||(e as any)?.code==='23505')return json({error:'Já existe um cadastro com esta matrícula, e-mail ou identificação.'},409);return json({error:'Não foi possível concluir a operação. Os dados preenchidos foram preservados.'},503);}
export async function GET(req:Request){try{
 const a=await actor(req);const u=new URL(req.url);const selected=city(u.searchParams.get('city')||'Condeúba');const isAdmin=a.role!=='policial';
 const [items,officers,categories,checks,movements,alerts,audit]=await Promise.all([
  stmt('SELECT * FROM inventory '+(isAdmin?'':'WHERE location=?')+' ORDER BY category,name,serial',...(isAdmin?[]:[selected])).all(),
  stmt(isAdmin?'SELECT * FROM officers ORDER BY city,rank,name':'SELECT id,name,rank,callsign,registration,city,role,active,validated FROM officers WHERE active=1 ORDER BY name').all(),
  stmt('SELECT * FROM categories ORDER BY name').all(),
  stmt('SELECT * FROM checks '+(isAdmin?'':'WHERE actor=?')+' ORDER BY created_at DESC',...(isAdmin?[]:[a.id])).all(),
  stmt('SELECT * FROM movements '+(isAdmin?'':'WHERE officer_id=?')+' ORDER BY withdrawn_at DESC',...(isAdmin?[]:[a.officer_id])).all(),
  stmt('SELECT * FROM alerts '+(isAdmin?'':'WHERE check_id IN (SELECT id FROM checks WHERE actor=?)')+' ORDER BY created_at DESC',...(isAdmin?[]:[a.id])).all(),
  isAdmin?stmt('SELECT * FROM audit ORDER BY created_at DESC LIMIT 300').all():Promise.resolve({results:[]}),
 ]);
 return json({user:a,items:items.results,officers:officers.results,categories:categories.results,checks:checks.results.map((c:any)=>({...c,entries:JSON.parse(c.entries),crew:JSON.parse(c.crew),crew_labels:JSON.parse(c.crew_labels||'[]')})),movements:movements.results,alerts:alerts.results,audit:audit.results,serverTime:new Date().toISOString()});
}catch(e){return error(e);}}
export async function POST(req:Request){try{
 const origin=req.headers.get('origin');if(origin&&origin!==(Deno.env.get('APP_ORIGIN')||'https://rapha11novais-source.github.io'))throw new UserError('Origem da solicitação inválida.',403);
 if(Number(req.headers.get('content-length')||0)>300000)throw new UserError('Solicitação muito grande.',413);
 const a=await actor(req);const b=await req.json() as any;const now=new Date().toISOString();const action=b.action;const id=textValue(b.id,100)||crypto.randomUUID();
 if(action==='save-check'){
  if(!a.officer_id)throw new UserError('Vincule seu acesso a um cadastro policial em Efetivo antes de conferir.');
  const selected=city(b.city);const crew=[...new Set<string>((Array.isArray(b.crew)?b.crew:[]).filter((x:any)=>typeof x==='string'))];
  if(!crew.includes(a.officer_id))crew.unshift(a.officer_id);
  if(crew.length>26)throw new UserError('Guarnição inválida.');
  const crewRows=await stmt(`SELECT id,rank,callsign,registration FROM officers WHERE active=1 AND validated=1 AND id IN (${crew.map(()=>'?').join(',')})`,...crew).all<any>();if(crewRows.results.length!==crew.length)throw new UserError('Há policial inativo ou pendente de validação na guarnição.');
  const old=await stmt('SELECT * FROM checks WHERE id=?',id).first<any>();
  if(old&&(old.actor!==a.id||old.status!=='rascunho'))throw new UserError('Este registro já foi finalizado ou pertence a outro policial.',403);
  const {results:current}=await stmt('SELECT * FROM inventory WHERE location=? AND quantity>0 ORDER BY id',selected).all<Item>();
  const incoming:Array<Entry>=Array.isArray(b.entries)?b.entries:[];const final=b.finalize===true;
  if(!current.length)throw new UserError('Não há materiais cadastrados para este município.');
  if(final&&(incoming.length!==current.length||new Set(incoming.map(e=>e.id)).size!==current.length))throw new UserError('Confira todos os materiais antes de finalizar.');
  const entries=current.map(i=>{
   const e=incoming.find(e=>e.id===i.id);const quantity=e?.quantity==null?null:integer(e.quantity,0,i.serial?1:1000000);const condition=textValue(e?.condition,40);const notes=textValue(e?.notes);const identification=e?.identification===true;
   if(final&&(!e||e.version!==i.version))throw new UserError('O inventário mudou durante a conferência. Reabra a conferência e revise os valores.',409);
   if(final&&(quantity===null||!CONDITIONS.includes(condition as any)))throw new UserError('Informe quantidade e condição de todos os materiais.');
   if(final&&condition==='Não encontrado'&&quantity!==0)throw new UserError('Material não encontrado deve ter quantidade conferida igual a zero.');
   if(final&&quantity===0&&condition!=='Não encontrado')throw new UserError('Selecione Não encontrado para materiais com quantidade zero.');
   const entry={id:i.id,quantity,condition,notes,identification,expected:i.quantity,version:i.version,name:i.name,serial:i.serial,category:i.category,city:i.city,location:i.location};
   if(final&&needsJustification(entry,i.quantity)&&notes.length<3)throw new UserError('Inclua uma justificativa para cada divergência, ausência ou condição ruim.');
   return entry;
  });
  const statements:any[]=[];const gid=crypto.randomUUID();
  if(old)statements.push(guard(gid,'SELECT COUNT(*)=1 FROM checks WHERE id=? AND actor=? AND status=? AND updated_at=?',id,a.id,'rascunho',old.updated_at));
  else statements.push(guard(gid,'SELECT COUNT(*)=0 FROM checks WHERE id=?',id));
  if(final){statements.push(guard(gid+'-count','SELECT COUNT(*)=? FROM inventory WHERE location=? AND quantity>0',entries.length,selected));entries.forEach((e,idx)=>statements.push(guard(gid+'-'+idx,'SELECT COUNT(*)=1 FROM inventory WHERE id=? AND version=? AND location=? AND quantity=?',e.id,e.version,selected,e.expected)));}
  statements.push(stmt('INSERT INTO checks(id,city,actor,officer_id,actor_name,crew,crew_labels,entries,notes,status,created_at,updated_at,finalized_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET city=excluded.city,crew=excluded.crew,crew_labels=excluded.crew_labels,entries=excluded.entries,notes=excluded.notes,status=excluded.status,updated_at=excluded.updated_at,finalized_at=excluded.finalized_at',id,selected,a.id,a.officer_id,a.name,JSON.stringify(crew),JSON.stringify(crew.map(id=>{const o=crewRows.results.find(o=>o.id===id);return o.rank+' '+o.callsign+' ('+o.registration+')'})),JSON.stringify(entries),textValue(b.notes),final?'finalizada':'rascunho',old?.created_at||now,now,final?now:null));
  if(final)entries.forEach(e=>{
   statements.push(stmt('UPDATE inventory SET condition=? WHERE id=?',e.condition,e.id));
   if(needsJustification(e,e.expected!))statements.push(stmt('INSERT INTO alerts(id,check_id,item_id,city,title,detail,status,created_at) VALUES(?,?,?,?,?,?,?,?)',crypto.randomUUID(),id,e.id,selected,e.condition==='Não encontrado'?'Material não encontrado':e.identification?'Identificação divergente':e.condition==='Ruim'?'Equipamento em estado ruim':'Divergência quantitativa',`${e.name}${e.serial?' · '+e.serial:''}. Previsto: ${e.expected}; conferido: ${e.quantity}. ${e.notes}`,'aberta',now));
  });
  statements.push(auditStmt(a,final?'Conferência finalizada':'Rascunho salvo',id,old,{city:selected,crew,entries},now),clearGuard(gid));
  if(final){entries.forEach((_,idx)=>statements.push(clearGuard(gid+'-'+idx)));statements.push(clearGuard(gid+'-count'));}
  await db().batch(statements);return json({ok:true,id});
 }
 admin(a);
 if(action==='save-item'){
  const old=await stmt('SELECT * FROM inventory WHERE id=?',id).first<Item>();const name=textValue(b.name,150);const cat=await stmt('SELECT * FROM categories WHERE id=?',textValue(b.category,100)).first<any>();if(!name||!cat)throw new UserError('Preencha nome e categoria.');
  const quantity=integer(b.quantity);const serial=textValue(b.serial,100)||null;if(cat.mode==='individual'&&(!serial||quantity!==1))throw new UserError('Itens individuais exigem identificação e quantidade 1.');
  const selected=city(b.city);const location=city(b.location||selected);const condition=textValue(b.condition,40)||'A conferir';if(![...CONDITIONS,'A conferir'].includes(condition as any))throw new UserError('Condição inválida.');
  if(old){const active=await stmt("SELECT id FROM movements WHERE item_id=? AND status!='devolvida'",id).first();if(active)throw new UserError('Regularize a cautela deste material antes de editar.');if(b.version!==old.version)throw new UserError('O material mudou. Atualize e tente novamente.',409);}
  if(old&&quantity!==old.quantity&&!textValue(b.reason))throw new UserError('Justifique a alteração do quantitativo previsto.');
  if(cat.id==='municoes'&&!textValue(b.caliber))throw new UserError('Informe o calibre das munições.');
  const next={id,name,category:cat.id,serial,manufacturer:textValue(b.manufacturer,100)||null,model:textValue(b.model,100)||null,caliber:textValue(b.caliber,40)||null,city:selected,location,quantity,condition,notes:textValue(b.notes),source:old?.source||'Cadastro administrativo',version:(old?.version||0)+1};
  const gid=crypto.randomUUID();const ops:any[]=[guard(gid,old?'SELECT COUNT(*)=1 FROM inventory WHERE id=? AND version=?':'SELECT COUNT(*)=0 FROM inventory WHERE id=?',id,...(old?[old.version]:[]))];
  ops.push(stmt('INSERT INTO inventory(id,name,category,serial,manufacturer,model,caliber,city,location,quantity,condition,notes,source,version) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,category=excluded.category,serial=excluded.serial,manufacturer=excluded.manufacturer,model=excluded.model,caliber=excluded.caliber,city=excluded.city,location=excluded.location,quantity=excluded.quantity,condition=excluded.condition,notes=excluded.notes,version=excluded.version',...Object.values(next)),auditStmt(a,'Material atualizado',id,old,{...next,reason:textValue(b.reason)},now),clearGuard(gid));await db().batch(ops);return json({ok:true});
 }
 if(action==='save-officer'){
  const old=await stmt('SELECT * FROM officers WHERE id=?',id).first<Officer>();const name=textValue(b.name,150),rank=textValue(b.rank,40),callsign=textValue(b.callsign,80),registration=textValue(b.registration,30);if(!name||!rank||!callsign||!/^\d{5,12}$/.test(registration))throw new UserError('Preencha nome, graduação, nome de guerra e matrícula numérica.');
  const role=textValue(b.role,40);if(!['policial','administrador','comando'].includes(role))throw new UserError('Perfil inválido.');if(a.role!=='comando'&&(role!=='policial'||old?.role==='comando'))throw new UserError('Somente o comando pode conceder perfis administrativos.',403);
  const email=textValue(b.email,200).toLowerCase()||null;if(email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))throw new UserError('Informe um e-mail válido.');
  if(old?.id===a.officer_id&&(role==='policial'||!b.active||!b.validated))throw new UserError('Seu próprio acesso de comando deve permanecer autorizado.');
  const next={id,name,rank,callsign,registration,city:city(b.city),role,email,active:b.active?1:0,validated:b.validated?1:0};
  await db().batch([stmt('INSERT INTO officers(id,name,rank,callsign,registration,city,role,email,active,validated) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,rank=excluded.rank,callsign=excluded.callsign,registration=excluded.registration,city=excluded.city,role=excluded.role,email=excluded.email,active=excluded.active,validated=excluded.validated',...Object.values(next)),auditStmt(a,'Cadastro policial atualizado',id,old,next,now)]);return json({ok:true});
 }
 if(action==='bind-self'){
  const officer=await stmt('SELECT * FROM officers WHERE id=? AND active=1 AND validated=1',textValue(b.officerId)).first<Officer>();if(!officer)throw new UserError('Escolha um cadastro ativo e validado.');if(officer.role==='policial')throw new UserError('O gestor inicial deve vincular um perfil administrativo.');
  if(officer.email&&officer.email.toLowerCase()!==a.email.toLowerCase())throw new UserError('Este cadastro já está vinculado a outro e-mail.');
  await db().batch([stmt('UPDATE officers SET email=? WHERE id=?',a.email.toLowerCase(),officer.id),stmt('UPDATE principals SET officer_id=?,role=?,name=? WHERE id=?',officer.id,officer.role,officer.rank+' '+officer.callsign,a.id),auditStmt(a,'Acesso vinculado ao cadastro',officer.id,a,{officerId:officer.id,email:a.email},now)]);return json({ok:true});
 }
 if(action==='save-category'){
  const name=textValue(b.name,80),mode=textValue(b.mode);if(!name||!['individual','quantidade'].includes(mode))throw new UserError('Informe nome e tipo de controle.');await db().batch([stmt('INSERT INTO categories(id,name,mode) VALUES(?,?,?)',id,name,mode),auditStmt(a,'Categoria criada',id,null,{name,mode},now)]);return json({ok:true});
 }
 if(action==='resolve-alert'){
  const resolution=textValue(b.resolution);if(resolution.length<3)throw new UserError('Registre a providência adotada.');const old=await stmt("SELECT * FROM alerts WHERE id=? AND status='aberta'",id).first();if(!old)throw new UserError('A ocorrência já está resolvida ou não existe.');await db().batch([stmt("UPDATE alerts SET status='resolvida',resolution=?,resolved_at=?,resolved_by=? WHERE id=? AND status='aberta'",resolution,now,a.name,id),auditStmt(a,'Ocorrência regularizada',id,old,{resolution},now)]);return json({ok:true});
 }
 if(action==='create-movement'){
  const i=await stmt('SELECT * FROM inventory WHERE id=?',textValue(b.itemId)).first<Item>();const o=await stmt('SELECT * FROM officers WHERE id=? AND active=1 AND validated=1',textValue(b.officerId)).first<Officer>();if(!i||!o)throw new UserError('Selecione material e policial ativo e validado.');
  const quantity=integer(b.quantity,1,i.quantity);const active=await stmt("SELECT id FROM movements WHERE item_id=? AND status!='devolvida'",i.id).first();if(active)throw new UserError('Já existe cautela aberta para este registro.');const destination=city(b.destination);const due=textValue(b.dueAt,50)||null;if(due&&(!Number.isFinite(Date.parse(due))||Date.parse(due)<Date.now()))throw new UserError('A devolução prevista deve ser futura.');const notes=textValue(b.notes);if(!notes)throw new UserError('Informe a finalidade da cautela.');
  const gid=crypto.randomUUID();await db().batch([guard(gid,"SELECT COUNT(*)=0 FROM movements WHERE item_id=? AND status!='devolvida'",i.id),stmt('INSERT INTO movements(id,item_id,item_name,officer_id,origin,destination,quantity,withdrawn_at,due_at,status,notes,created_by) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',id,i.id,i.name+(i.serial?' · '+i.serial:''),o.id,i.location,destination,quantity,now,due,'aguardando',notes,a.name),auditStmt(a,'Cautela registrada',id,null,{item:i.id,officer:o.id,origin:i.location,destination,quantity,dueAt:due,notes},now),clearGuard(gid)]);return json({ok:true});
 }
 if(action==='receive-movement'||action==='return-movement'){
  const m=await stmt('SELECT * FROM movements WHERE id=?',id).first<any>();if(!m)throw new UserError('Cautela não encontrada.');const receiving=action==='receive-movement';if(m.status!==(receiving?'aguardando':'recebida'))throw new UserError('A cautela não está disponível para esta operação.');
  const i=await stmt('SELECT * FROM inventory WHERE id=?',m.item_id).first<Item>();if(!i)throw new UserError('Material não encontrado.');const gid=crypto.randomUUID();const ops:any[]=[guard(gid,'SELECT COUNT(*)=1 FROM movements WHERE id=? AND status=?',id,m.status)];
  if(receiving){
   ops.push(guard(gid+'-stock','SELECT COUNT(*)=1 FROM inventory WHERE id=? AND quantity>=? AND version=?',i.id,m.quantity,i.version));
   if(m.quantity===i.quantity)ops.push(stmt('UPDATE inventory SET location=?,version=version+1 WHERE id=?',m.destination,i.id));
   else {ops.push(stmt('UPDATE inventory SET quantity=quantity-?,version=version+1 WHERE id=?',m.quantity,i.id),stmt('INSERT INTO inventory(id,name,category,serial,manufacturer,model,caliber,city,location,quantity,condition,notes,source,version) SELECT ?,name,category,NULL,manufacturer,model,caliber,city,?,?,condition,notes,source,1 FROM inventory WHERE id=?','lote-'+id,m.destination,m.quantity,i.id));}
   ops.push(stmt("UPDATE movements SET status='recebida',received_at=? WHERE id=?",now,id),clearGuard(gid+'-stock'));
  }else{
   const lot=await stmt('SELECT * FROM inventory WHERE id=?','lote-'+id).first<Item>();
   if(lot){const other=await stmt("SELECT id FROM movements WHERE item_id=? AND status!='devolvida'",lot.id).first();if(other)throw new UserError('Há outra cautela em andamento para o lote recebido.');ops.push(guard(gid+'-lot','SELECT COUNT(*)=1 FROM inventory WHERE id=? AND quantity=? AND version=?',lot.id,m.quantity,lot.version),stmt('UPDATE inventory SET quantity=quantity+?,version=version+1 WHERE id=?',m.quantity,i.id),stmt('DELETE FROM inventory WHERE id=?',lot.id),clearGuard(gid+'-lot'));}
   else ops.push(stmt('UPDATE inventory SET location=?,version=version+1 WHERE id=?',m.origin,i.id));
   ops.push(stmt("UPDATE movements SET status='devolvida',returned_at=? WHERE id=?",now,id));
  }
  ops.push(auditStmt(a,receiving?'Recebimento confirmado':'Devolução confirmada',id,m,{status:receiving?'recebida':'devolvida'},now),clearGuard(gid));await db().batch(ops);return json({ok:true});
 }
 throw new UserError('Operação não reconhecida.');
}catch(e){return error(e);}}
