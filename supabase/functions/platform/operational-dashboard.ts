import {platoonOf,needsJustification} from './domain.ts';
const list=(value:any):any[]=>typeof value==='string'?JSON.parse(value):value||[];
const units=(load:any)=>list(load.entries).reduce((sum:number,e:any)=>sum+Number(e.quantity||0),0);

export function operationalDashboard({cities,checks,loads,alerts,movements,start,end,canReadDetails}:{cities:readonly string[];checks:any[];loads:any[];alerts:any[];movements:any[];start:string;end:string;canReadDetails:(city:string)=>boolean}){
 return cities.map(city=>{
  const localChecks=checks.filter(c=>c.city===city&&!c.deleted_at);
  const inPeriod=(row:any)=>row.service_day>=start&&row.service_day<=end;
  const completed=localChecks.filter(c=>c.status==='finalizada'&&inPeriod(c));
  const current=completed[0],draft=localChecks.find(c=>c.status==='rascunho'&&inPeriod(c));
  const latest=localChecks.find(c=>c.status==='finalizada');
  const entries=current?list(current.entries):[];
  const pending=alerts.filter(a=>a.city===city&&a.status==='aberta');
  const localLoads=loads.filter(l=>l.city===city);
  const periodLoads=localLoads.filter(inPeriod),active=localLoads.filter(l=>l.status==='ativa');
  const crew=current?list(current.crew):[];
  const registered=new Set(periodLoads.filter(l=>l.check_id===current?.id).map(l=>l.officer_id));
  const details=canReadDetails(city);
  return {
   city,platoon_id:platoonOf(city),status:pending.length||entries.some(e=>needsJustification(e,e.expected||0))?'divergencia':current?'conferida':draft?'andamento':'pendente',
   last_at:latest?.finalized_at||null,responsible:current?.actor_name||latest?.actor_name||'',crew:current?list(current.crew_labels):[],checked:entries.length,
   missing:entries.filter(e=>e.condition==='Não encontrado').length,divergences:entries.filter(e=>needsJustification(e,e.expected||0)).length,pending:pending.length,in_progress:!!draft,
   loads:active.length,loaded_quantity:active.reduce((sum,l)=>sum+units(l),0),loads_in_period:periodLoads.length,units_in_period:periodLoads.reduce((sum,l)=>sum+units(l),0),crew_total:crew.length,crew_loaded:crew.filter(id=>registered.has(id)).length,
   conference:{status:current?'finalizada':draft?'rascunho':'pendente',by_commander:!!current,at:current?.finalized_at||draft?.updated_at||null,day:current?.service_day||draft?.service_day||null,responsible:current?.actor_name||draft?.actor_name||'',count:completed.length},
   details_allowed:details,
   conference_records:details?completed.map(c=>({id:c.id,day:c.service_day,at:c.finalized_at,responsible:c.actor_name,crew:list(c.crew_labels),checked:list(c.entries).length})):[],
   load_records:details?localLoads.filter(l=>inPeriod(l)||l.status==='ativa').map(l=>({id:l.id,officer_name:l.officer_name,registration:l.registration||'',day:l.service_day,at:l.created_at,returned_at:l.returned_at,status:l.status,in_period:inPeriod(l),quantity:units(l),entries:list(l.entries).map(e=>({name:e.name,serial:e.serial||null,quantity:e.quantity,condition:e.condition}))})):[],
   last_movements:movements.filter(m=>m.origin===city||m.destination===city).slice(0,3).map(m=>({at:m.withdrawn_at,status:m.status,quantity:m.quantity,origin:m.origin,destination:m.destination}))
  };
 });
}
