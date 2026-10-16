import {useEffect,useState} from 'react';
import {vehicleAttachment} from '@/lib/api';
import {Dialog,DialogContent,DialogTitle} from '@/components/ui/dialog';
import {CameraOff,Expand,RefreshCw,X} from 'lucide-react';
export type VehiclePhotoRef={id:string;original_name:string;content_type:string};
export default function VehiclePhoto({photo,name,compact=false}:{photo?:VehiclePhotoRef|null;name:string;compact?:boolean}){
 const [url,setUrl]=useState(''),[error,setError]=useState(false),[loading,setLoading]=useState(false),[open,setOpen]=useState(false),[attempt,setAttempt]=useState(0);
 useEffect(()=>{let alive=true;setUrl('');setError(false);setOpen(false);if(photo){setLoading(true);void vehicleAttachment(photo.id).then(d=>{if(alive)setUrl(d.url)}).catch(()=>{if(alive)setError(true)}).finally(()=>{if(alive)setLoading(false)});}else setLoading(false);return()=>{alive=false}},[photo?.id,attempt]);
 async function enlarge(){if(!photo)return;setLoading(true);try{const d=await vehicleAttachment(photo.id);setUrl(d.url);setError(false);setOpen(true);}catch{setError(true)}finally{setLoading(false)}}
 const label=loading?'Carregando foto…':error?'Foto indisponível':photo?'Ampliar foto de '+name:'Sem foto';
 return <div className={'vehicle-cover'+(compact?' compact':'')}><button type="button" className="vehicle-cover-image" aria-label={label} disabled={!photo||loading} onClick={()=>error?setAttempt(n=>n+1):void enlarge()}>{url&&!error?<><img src={url} alt={'Foto de '+name} loading="lazy" onError={()=>setError(true)}/><span><Expand size={15}/> Ampliar</span></>:<div className="vehicle-no-photo"><CameraOff size={compact?22:36}/><strong>{loading?'Carregando…':error?'Foto indisponível':'Sem foto'}</strong>{error&&<small><RefreshCw size={13}/> Tentar novamente</small>}</div>}</button>{open&&<Dialog open onOpenChange={setOpen}><DialogContent className="modal vehicle-image-dialog" aria-describedby={undefined} showCloseButton={false}><div className="modal-head"><DialogTitle>Foto de {name}</DialogTitle><button className="icon-btn" aria-label="Fechar foto ampliada" onClick={()=>setOpen(false)}><X/></button></div><img src={url} alt={'Foto ampliada de '+name}/><p>A fotografia original é exibida sem cortes.</p></DialogContent></Dialog>}</div>;
}
