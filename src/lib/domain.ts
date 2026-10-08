export const CITIES = ['Condeúba', 'Cordeiros', 'Mortugaba'] as const;
export const CONDITIONS = ['Ótimo','Bom','Ruim','Não encontrado'] as const;
export const ROLE_LABELS:Record<string,string> = {comando:'Comando do Pelotão', administrador:'Administrador autorizado', policial:'Policial militar'};
export type Item = { id:string; name:string; category:string; serial:string|null; manufacturer:string|null; model:string|null; caliber:string|null; city:string; location:string; quantity:number; condition:string; notes:string; source:string; version:number };
export type Officer = {id:string; name:string; rank:string; callsign:string; registration:string; city:string; role:string; email:string|null; active:number; validated:number};
export type Entry = {id:string; quantity:number|null; condition:string; notes:string; identification:boolean; expected?:number; version?:number; name?:string; serial?:string|null; category?:string; city?:string; location?:string;};
export type Check = {id:string;city:string;actor:string;officer_id:string|null;actor_name:string;crew:string[];crew_labels?:string[];entries:Entry[];notes:string;status:string;created_at:string;updated_at:string;finalized_at:string|null};
export type Movement={id:string;item_id:string;item_name:string;officer_id:string;origin:string;destination:string;quantity:number;withdrawn_at:string;due_at:string|null;received_at:string|null;returned_at:string|null;status:string;notes:string;created_by:string};
export type Alert={id:string;check_id:string;item_id:string;city:string;title:string;detail:string;status:string;created_at:string;resolved_at:string|null;resolution:string|null;resolved_by:string|null};
export function localDay(date=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);}
export function dateTime(value:string|null){return value?new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'}).format(new Date(value)):'—';}
export function needsJustification(e:Entry,expected:number){return e.quantity!==expected||['Ruim','Não encontrado'].includes(e.condition)||e.identification;}
