import {stmt,db,general,allow,UserError,textValue,auditStmt,type Actor} from './server.ts';
import {PLATOONS} from './domain.ts';
export async function extraAction(a:Actor,b:any,now:string){
 if(b.action==='set-links'){
  general(a);const o=await stmt('SELECT * FROM officers WHERE id=?',textValue(b.officerId)).first<any>();if(!o||o.deleted_at)throw new UserError('Cadastro não disponível.');
  const links=Array.isArray(b.platoons)?[...new Set<string>(b.platoons)]:null;if(!links||links.some(p=>!PLATOONS.some(x=>x.id===p)))throw new UserError('Vínculos inválidos.');
  const old=await stmt('SELECT platoon_id FROM officer_platoons WHERE officer_id=? AND active=1',o.id).all<any>();
  await db().batch([stmt('UPDATE officer_platoons SET active=0 WHERE officer_id=?',o.id),...links.map(p=>stmt('INSERT INTO officer_platoons(officer_id,platoon_id,active) VALUES(?,?,1) ON CONFLICT(officer_id,platoon_id) DO UPDATE SET active=1',o.id,p)),auditStmt(a,'Vínculos operacionais alterados',o.id,{...o,platoons:old.results.map(x=>x.platoon_id)},{city:o.city,home_platoon:o.home_platoon,platoons:links},now)]);return {ok:true};
 }
 if(['delete-item','restore-item'].includes(b.action)){
  const reason=textValue(b.reason);if(reason.length<3)throw new UserError('Informe o motivo.');
  await db().transaction(async tx=>{const s=(q:string,...v:unknown[])=>tx.prepare(q).bind(...v);const i=await s('SELECT * FROM inventory WHERE id=? FOR UPDATE',textValue(b.id)).first<any>();if(!i)throw new UserError('Material não encontrado.');allow(a,'materials',i.city);allow(a,'materials',i.location);
   const restoring=b.action==='restore-item';if(restoring&&!i.deleted_at||!restoring&&i.deleted_at)throw new UserError('Situação do material já alterada.');
   if(!restoring&&(await s("SELECT load_id FROM load_items li JOIN loads l ON l.id=li.load_id WHERE li.item_id=? AND l.status='ativa'",i.id).first()||await s("SELECT id FROM movements WHERE item_id=? AND status!='devolvida'",i.id).first()))throw new UserError('Devolva as cargas e cautelas antes de excluir o material.');
   await tx.batch([s('UPDATE inventory SET deleted_at=?,deleted_by=?,deletion_reason=?,version=version+1 WHERE id=?',restoring?null:now,restoring?null:a.id,restoring?null:reason,i.id),auditStmt(a,restoring?'Material restaurado':'Material excluído logicamente',i.id,i,{city:i.city,location:i.location,reason,deleted_at:restoring?null:now},now)]);
  });return {ok:true};
 }
 if(b.action==='rectify-check'){
  const c=await stmt("SELECT * FROM checks WHERE id=? AND status='finalizada'",textValue(b.id)).first<any>();if(!c)throw new UserError('Conferência finalizada não encontrada.');allow(a,'materials',c.city);const reason=textValue(b.reason),correction=textValue(b.correction,6000);if(reason.length<3||correction.length<10)throw new UserError('Descreva o motivo e a retificação.');
  const id=crypto.randomUUID();await db().batch([stmt('INSERT INTO check_corrections(id,check_id,actor,actor_name,actor_registration,reason,correction,created_at) VALUES(?,?,?,?,?,?,?,?)',id,c.id,a.id,a.name,a.registration||null,reason,correction,now),auditStmt(a,'Retificação de conferência registrada',c.id,null,{city:c.city,correctionId:id,reason,correction},now)]);return {ok:true};
 }
 return null;
}
