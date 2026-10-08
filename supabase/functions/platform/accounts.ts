import {admin,db,UserError,textValue,auditStmt,mutableUser,type Actor} from './server.ts';
export async function accountAction(a:Actor,b:any,now:string){
 if(!['delete-user','restore-user','set-user-role'].includes(b.action))return null;
 admin(a);const id=textValue(b.officerId||b.id,100);await mutableUser(id);
 if(id===a.officer_id&&b.action==='delete-user')throw new UserError('Outro administrador deve excluir seu cadastro.');
 const reason=textValue(b.reason);if(reason.length<3)throw new UserError('Informe o motivo desta alteração.');
 await db().transaction(async tx=>{
  const s=(q:string,...v:unknown[])=>tx.prepare(q).bind(...v);const o=await s('SELECT * FROM officers WHERE id=? FOR UPDATE',id).first<any>();if(!o)throw new UserError('Usuário não encontrado.');
  if(b.action==='delete-user'){
   if(o.deleted_at)throw new UserError('O usuário já foi excluído.');
   if(await s("SELECT id FROM loads WHERE officer_id=? AND status='ativa'",id).first()||await s("SELECT id FROM movements WHERE officer_id=? AND status!='devolvida'",id).first())throw new UserError('Registre a devolução das cargas e cautelas antes de excluir o usuário.');
   await tx.batch([s('UPDATE officers SET active=0,validated=0,deleted_at=?,deleted_by=?,deletion_reason=? WHERE id=?',now,a.id,reason,id),auditStmt(a,'Usuário excluído',id,o,{reason,deleted_at:now,accessBlocked:true},now)]);
  }else if(b.action==='restore-user'){
   if(!o.deleted_at)throw new UserError('O usuário não está excluído.');
   await tx.batch([s('UPDATE officers SET deleted_at=NULL,deleted_by=NULL,deletion_reason=NULL WHERE id=?',id),auditStmt(a,'Cadastro de usuário restaurado',id,o,{reason,requiresValidation:true},now)]);
  }else{
   const role=textValue(b.role,40);if(!['policial','administrador','comando'].includes(role))throw new UserError('Perfil inválido.');if(o.deleted_at)throw new UserError('Restaure o cadastro antes de alterar o perfil.');if(id===a.officer_id&&role==='policial')throw new UserError('Outro administrador deve alterar seu perfil.');
   await tx.batch([s('UPDATE officers SET role=? WHERE id=?',role,id),auditStmt(a,'Perfil de acesso alterado',id,{role:o.role},{role,reason},now)]);
  }
 });return {ok:true};
}
