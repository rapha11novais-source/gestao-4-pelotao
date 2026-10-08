import {createClient,type SupabaseClient} from '@supabase/supabase-js';
let client:SupabaseClient|null=null;
let config:{supabaseUrl:string;supabasePublishableKey:string};
export async function initialize(){const r=await fetch(import.meta.env.BASE_URL+'config.json',{cache:'no-store'});if(!r.ok)throw Error('A configuração do acesso não pôde ser carregada.');config=await r.json();if(!config.supabaseUrl||!config.supabasePublishableKey)throw Error('A conexão com o Supabase está em preparação. O acesso será liberado após a configuração do banco.');if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(config.supabaseUrl))throw Error('Endereço de acesso inválido.');client=createClient(config.supabaseUrl,config.supabasePublishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});return client;}
export function supabase(){if(!client)throw Error('O acesso ainda não foi inicializado.');return client;}
async function request(method:'GET'|'POST',payload?:unknown,city='Condeúba'){
 const {data:{session},error}=await supabase().auth.getSession();if(error||!session)throw Error('Entre com sua conta para continuar.');
 const r=await fetch(config.supabaseUrl.replace(/\/$/,'')+'/functions/v1/platform?city='+encodeURIComponent(city),{method,headers:{apikey:config.supabasePublishableKey,Authorization:'Bearer '+session.access_token,...(method==='POST'?{'Content-Type':'application/json'}:{})},body:method==='POST'?JSON.stringify(payload):undefined});
 const body=await r.json().catch(()=>({error:'O serviço está indisponível. Tente novamente.'}));if(!r.ok)throw Error(body.error||body.message||'Não foi possível concluir a operação.');return body;
}
export const loadPlatform=(city:string)=>request('GET',undefined,city);
export const savePlatform=(payload:unknown)=>request('POST',payload);
export async function logout(){const {error}=await supabase().auth.signOut();if(error)throw error;location.assign(import.meta.env.BASE_URL);}
