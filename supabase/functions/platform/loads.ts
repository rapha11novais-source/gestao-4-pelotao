import {stmt,db,UserError,integer,textValue,auditStmt,manager,authAdmin,type Actor} from './server.ts';
import {localDay,type Item} from './domain.ts';
export const reservedSQL=`COALESCE((SELECT SUM(li.quantity) FROM load_items li JOIN loads l ON l.id=li.load_id WHERE li.item_id=i.id AND l.status='ativa'),0)+COALESCE((SELECT SUM(m.quantity) FROM movements m WHERE (m.status='aguardando' AND m.item_id=i.id) OR (m.status='recebida' AND (i.id='lote-'||m.id OR (m.item_id=i.id AND NOT EXISTS(SELECT 1 FROM inventory x WHERE x.id='lote-'||m.id))))),0)`;
export const stockQuery=`SELECT i.*, (${reservedSQL}) AS reserved FROM inventory i`;
export async function personalLoads(a:Actor){const rows=await stmt('SELECT * FROM loads '+(a.role==='policial'?'WHERE actor=? ':'')+'ORDER BY created_at DESC',...(a.role==='policial'?[a.id]:[])).all<any>();return rows.results.map(l=>({...l,entries:JSON.parse(l.entries)}));}
export async function report(a:Actor,id:string){const l=await stmt('SELECT * FROM loads WHERE id=?',id).first<any>();if(!l||a.role==='policial'&&l.actor!==a.id)throw new UserError('Relatório não disponível para este acesso.',403);const c=await stmt('SELECT * FROM checks WHERE id=?',l.check_id).first<any>();if(!c||c.city!==l.city||!JSON.parse(c.crew).includes(l.officer_id))throw new UserError('O relatório não corresponde ao serviço registrado.',403);return {load:{...l,entries:JSON.parse(l.entries)},check:{...c,crew:JSON.parse(c.crew),entries:JSON.parse(c.entries)},officer:await stmt('SELECT id,name,registration FROM officers WHERE id=?',l.officer_id).first()};}
export async function loadAction(a:Actor,b:any,now:string){
 const today=localDay(new Date(now));
 if(b.action==='set-officer-password'){
  manager(a);const o=await stmt('SELECT * FROM officers WHERE id=?',textValue(b.officerId)).first<any>();if(!o||!o.active||!o.validated)throw new UserError('Valide e ative o cadastro antes de criar o acesso.');
  const password=typeof b.password==='string'?b.password:'';if(password.length<12||new TextEncoder().encode(password).length>72)throw new UserError('Use uma senha com pelo menos 12 caracteres e até 72 bytes.');
  const identity=o.registration+'@accounts.invalid';const existing=(await stmt('SELECT id FROM auth.users WHERE lower(email)=?',identity).first<any>())?.id;
  const client=authAdmin();let uid=existing;if(existing){const {error}=await client.auth.admin.updateUserById(existing,{password});if(error)throw new UserError('Não foi possível redefinir a senha.',503);}else{const {data,error}=await client.auth.admin.createUser({email:identity,password,email_confirm:true,user_metadata:{full_name:o.name}});if(error||!data.user)throw new UserError('Não foi possível criar o acesso.',503);uid=data.user.id;}
  await db().batch([stmt("UPDATE principals SET officer_id=NULL,name='4º Pelotão' WHERE id=? AND lower(email)=(SELECT lower(value) FROM settings WHERE key='owner_email')",o.auth_user_id||''),stmt('UPDATE officers SET auth_user_id=? WHERE id=?',uid,o.id),auditStmt(a,existing?'Senha de acesso redefinida':'Acesso por matrícula criado',o.id,null,{registration:o.registration,accountId:uid},now)]);
  return {ok:true,login:o.registration};
 }
 if(b.action==='delete-check'){
  manager(a);const reason=textValue(b.reason);if(reason.length<3)throw new UserError('Informe o motivo da exclusão.');
  await db().transaction(async tx=>{const s=(q:string,...v:unknown[])=>tx.prepare(q).bind(...v);const c=await s('SELECT * FROM checks WHERE id=? FOR UPDATE',textValue(b.id)).first<any>();if(!c||c.deleted_at)throw new UserError('Conferência não encontrada ou já excluída.');if(await s("SELECT id FROM loads WHERE check_id=? AND status='ativa'",c.id).first())throw new UserError('Registre a devolução das cargas vinculadas antes de excluir a conferência.');await tx.batch([s('UPDATE checks SET deleted_at=?,deleted_by=?,deletion_reason=? WHERE id=?',now,a.id,reason,c.id),auditStmt(a,'Conferência excluída pelo gestor',c.id,c,{reason,deleted_at:now},now)]);});return {ok:true};
 }
 if(b.action==='save-load'){
  if(!a.officer_id)throw new UserError('O acesso deve estar vinculado a um policial.');const id=crypto.randomUUID();
  await db().transaction(async tx=>{
   const s=(q:string,...v:unknown[])=>tx.prepare(q).bind(...v);const c=await s("SELECT * FROM checks WHERE id=? AND status='finalizada' AND deleted_at IS NULL FOR UPDATE",textValue(b.checkId)).first<any>();
   if(!c||c.service_day!==today||!JSON.parse(c.crew).includes(a.officer_id))throw new UserError('Sua carga exige a conferência de hoje e sua participação na guarnição.',403);
   if(await s('SELECT id FROM loads WHERE (actor=? OR officer_id=?) AND service_day=?',a.id,a.officer_id,today).first())throw new UserError('Você já registrou sua única carga de hoje.',409);
   const input=(Array.isArray(b.entries)?b.entries:[]).filter((e:any)=>e.quantity!==0);if(!input.length||input.length>300||new Set(input.map((e:any)=>e.id)).size!==input.length)throw new UserError('Selecione pelo menos um material, sem repetir itens.');
   const ids=input.map((e:any)=>textValue(e.id,100)).sort();await s(`SELECT id FROM inventory WHERE id IN (${ids.map(()=>'?').join(',')}) ORDER BY id FOR UPDATE`,...ids).all();
   const rows=await s(stockQuery+` WHERE i.id IN (${ids.map(()=>'?').join(',')}) ORDER BY i.id`,...ids).all<Item&{reserved:number}>();if(rows.results.length!==ids.length)throw new UserError('Há material indisponível nesta seleção.');const checked=JSON.parse(c.entries);
   const entries=rows.results.map(i=>{const e=input.find((e:any)=>e.id===i.id);const found=checked.find((x:any)=>x.id===i.id);const amount=integer(e.quantity,1,i.serial?1:1000000);const available=Math.max(0,Math.min(i.quantity,found?.quantity??0)-Number(i.reserved));if(i.location!==c.city||!found||amount>available)throw new UserError(`${i.name}: quantidade disponível insuficiente. Atualize a carga e revise.`,409);return {id:i.id,name:i.name,serial:i.serial,category:i.category,city:i.city,location:i.location,quantity:amount,condition:found.condition};});
   await tx.batch([s('INSERT INTO loads(id,check_id,actor,officer_id,officer_name,city,service_day,entries,notes,status,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',id,c.id,a.id,a.officer_id,a.name,c.city,today,JSON.stringify(entries),textValue(b.notes),'ativa',now),...entries.map(e=>s('INSERT INTO load_items(load_id,item_id,quantity) VALUES(?,?,?)',id,e.id,e.quantity)),auditStmt(a,'Carga individual assumida',id,null,{checkId:c.id,city:c.city,entries},now)]);
  });return {ok:true,id};
 }
 if(b.action==='return-load'){
  if(b.confirmReturn!==true)throw new UserError('Confirme a devolução física dos materiais.');
  await db().transaction(async tx=>{const s=(q:string,...v:unknown[])=>tx.prepare(q).bind(...v);const l=await s('SELECT * FROM loads WHERE id=? FOR UPDATE',textValue(b.id)).first<any>();if(!l||a.role==='policial'&&l.actor!==a.id)throw new UserError('Esta carga não pertence a você.',403);if(l.status!=='ativa')throw new UserError('A carga já foi devolvida.');if(l.actor!==a.id&&!textValue(b.notes))throw new UserError('Justifique a devolução registrada pelo gestor.');const ids=JSON.parse(l.entries).map((e:any)=>e.id).sort();await s(`SELECT id FROM inventory WHERE id IN (${ids.map(()=>'?').join(',')}) ORDER BY id FOR UPDATE`,...ids).all();await tx.batch([s("UPDATE loads SET status='devolvida',returned_at=? WHERE id=?",now,l.id),auditStmt(a,'Carga individual devolvida',l.id,l,{returned_at:now,notes:textValue(b.notes)},now)]);});return {ok:true};
 }
 return null;
}
