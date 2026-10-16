import {db,UserError,type Actor} from './server.ts';
const read=(v:any,fallback:any)=>v==null?fallback:typeof v==='string'?JSON.parse(v):v;

// Membership in this exact service, including historical membership, permits the
// complete team report. This does not grant inventory access or administrative rights.
export async function unifiedServiceReport(a:Actor,id:string){
 return db().transaction(async tx=>{
  const q=(sql:string,...args:any[])=>tx.prepare(sql).bind(...args);
  const service=await q('SELECT * FROM services WHERE id=?',id).first<any>();
  const members=(await q('SELECT * FROM service_members WHERE service_id=? ORDER BY CASE WHEN officer_id=? THEN 0 ELSE 1 END,name,officer_id',id,service?.commander_officer_id||'').all<any>()).results;
  const own=members.some(m=>m.officer_id===a.officer_id);
  if(!service||!a.is_global&&!own&&!a.managementCities?.includes(service.city))throw new UserError('Relatório não disponível para este acesso.',403);
  const raw=await q('SELECT * FROM checks WHERE id=?',id).first<any>();
  if(!raw||raw.status!=='finalizada'||!service.conference_at&&!service.legacy)throw new UserError('Finalize a conferência inicial para emitir o relatório do serviço.',409);
  const loads=(await q('SELECT * FROM loads WHERE check_id=? ORDER BY created_at,id',id).all<any>()).results;
  const balances=(await q('SELECT i.* FROM load_items i JOIN loads l ON l.id=i.load_id WHERE l.check_id=?',id).all<any>()).results;
  const returns=(await q('SELECT r.* FROM load_returns r JOIN loads l ON l.id=r.load_id WHERE l.check_id=? ORDER BY r.created_at,r.id',id).all<any>()).results;
  const events=(await q('SELECT * FROM service_events WHERE service_id=? ORDER BY created_at,id',id).all<any>()).results;
  const vehicleEvents=(await q("SELECT id,vehicle_id,kind,actor_name,actor_registration,created_at,payload FROM vehicle_events WHERE check_id=? AND kind IN('cadastro','saida','conferencia','observacao') ORDER BY created_at,id",id).all<any>()).results;
  const initial=read(raw.vehicle_entries,[]);
  const vehicleIds=[...new Set([...initial.map((v:any)=>v.id),...vehicleEvents.map(v=>v.vehicle_id)])];
  const custody=vehicleIds.length?(await q(`SELECT id,type,physical,entered_at,reason,notes FROM vehicle_custodies WHERE id IN(${vehicleIds.map(()=>'?').join(',')})`,...vehicleIds).all<any>()).results:[];
  const history=vehicleIds.length?(await q(`SELECT vehicle_id,kind,created_at,payload FROM vehicle_events WHERE vehicle_id IN(${vehicleIds.map(()=>'?').join(',')}) AND kind IN('cadastro','correcao') ORDER BY created_at,id`,...vehicleIds).all<any>()).results:[];
  function vehicleAt(vid:string,at:string,physical?:any){
   const h=history.filter(h=>h.vehicle_id===vid&&Date.parse(h.created_at)<=Date.parse(at)).at(-1);
   const saved=h?(h.kind==='correcao'?h.payload.after:h.payload):null;
   const current=custody.find(v=>v.id===vid);
   return {id:vid,type:saved?.type||current?.type||'',physical:physical||saved?.physical||current?.physical||{},entered_at:saved?.entered_at||current?.entered_at||null,reason:saved?.reason||'',notes:saved?.notes||'',identification_source:physical||saved?'Registro histórico':'Cadastro atual; identificação histórica indisponível no registro anterior'};
  }
  const vehicleEntries=vehicleEvents.filter(e=>e.kind==='cadastro').map(e=>({...vehicleAt(e.vehicle_id,e.created_at),...e.payload,id:e.vehicle_id,registered_at:e.created_at,actor_name:e.actor_name,actor_registration:e.actor_registration}));
  const vehicleExits=vehicleEvents.filter(e=>e.kind==='saida').map(e=>({...vehicleAt(e.vehicle_id,e.created_at),...e.payload.vehicle_snapshot,...e.payload,...(e.payload.vehicle_snapshot?{identification_source:'Registro histórico'}:{}),id:e.vehicle_id,registered_at:e.created_at,actor_name:e.actor_name,actor_registration:e.actor_registration}));
  const corrections=(await q('SELECT * FROM check_corrections WHERE check_id=? ORDER BY created_at,id',id).all<any>()).results;
  const alerts=(await q('SELECT id,title,detail,status,created_at FROM alerts WHERE check_id=? ORDER BY created_at,id',id).all<any>()).results;
  const vehicleAlerts=(await q('SELECT id,vehicle_id,kind,detail,status,created_at,seen_at,resolved_at,resolved_name,resolution FROM vehicle_alerts WHERE check_id=? ORDER BY created_at,id',id).all<any>()).results;
  const attachments=(await q('SELECT id,phase,item_id,original_name,actor_name,actor_registration,created_at FROM service_attachments WHERE service_id=? ORDER BY created_at,id',id).all<any>()).results;
  const formalCurrent=(await q("SELECT DISTINCT m.*,i.serial,i.model,i.manufacturer,i.caliber,i.category FROM movements m LEFT JOIN inventory i ON i.id=CASE WHEN EXISTS(SELECT 1 FROM inventory n WHERE n.id='lote-'||m.id) THEN 'lote-'||m.id ELSE m.item_id END WHERE m.officer_id IN(SELECT officer_id FROM service_members WHERE service_id=?) AND m.destination=? AND m.withdrawn_at<=? AND (m.returned_at IS NULL OR m.returned_at>=?)",id,service.city,service.ended_at||new Date().toISOString(),service.conference_at||service.started_at).all<any>()).results;
  const formal=service.status==='encerrado'?[...new Map([...members.flatMap(m=>m.closing?.formal_movements||[]),...(service.closing?.formal_movements||[])].map(m=>[m.id,m])).values()]:formalCurrent;
  return {version:1,generated_at:new Date().toISOString(),partial:service.status!=='encerrado',service:{...service,crew:read(service.crew,[])},members,
   check:{...raw,crew:read(raw.crew,[]),crew_labels:read(raw.crew_labels,[]),entries:read(raw.entries,[]),vehicle_entries:initial,corrections},
   loads:loads.map(l=>({...l,entries:read(l.entries,[]).map((e:any)=>({...e,...balances.find(b=>b.load_id===l.id&&b.item_id===e.id)}))})),
   formal_movements:formal,returns,events,attachments,alerts,vehicle_alerts:vehicleAlerts,
   vehicles:{initial:initial.map((v:any)=>({...vehicleAt(v.id,v.at||service.conference_at||raw.finalized_at,v.physical),...v})),registered:vehicleEntries,exited:vehicleExits,events:vehicleEvents}};
 },{readOnly:true});
}
