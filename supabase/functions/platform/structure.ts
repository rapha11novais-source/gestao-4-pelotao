import {AsyncLocalStorage} from 'node:async_hooks';
import {database} from './db.ts';
export type Structure={platoons:any[];units:any[];municipalities:any[]};
const context=new AsyncLocalStorage<Structure>();
export function structure(){const s=context.getStore();if(!s)throw Error('Estrutura operacional não carregada.');return s;}
export async function withStructure<T>(work:()=>Promise<T>){
 const [p,u,m]=await Promise.all([database.prepare('SELECT * FROM platoons ORDER BY name').all(),database.prepare('SELECT * FROM cities ORDER BY name').all(),database.prepare('SELECT * FROM municipalities ORDER BY name').all()]);
 return context.run({platoons:p.results.map((x:any)=>({...x,cities:u.results.filter((c:any)=>c.platoon_id===x.id&&c.active&&x.active).map((c:any)=>c.name)})),units:u.results,municipalities:m.results},work);
}
export const catalogPlatoons=()=>structure().platoons.filter(p=>p.active);
export const catalogCities=()=>structure().units.filter(u=>u.active&&structure().platoons.some(p=>p.id===u.platoon_id&&p.active)).map(u=>u.name);
