(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2009 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

include Frame

(* Samples of ticks, and vice versa. *)
let sot = audio_of_master
let tos = master_of_audio

let content b pos =
  let stop,content = content b (tos pos) in
    assert (stop = Lazy.force size) ;
    assert (Array.length content.video = 0) ;
    assert (Array.length content.midi = 0) ;
    content.audio

let content_of_type ~channels b pos =
  let ctype = { audio = channels ; video = 0 ; midi = 0 } in
  let content = content_of_type b (tos pos) ctype in
    content.audio

let to_s16le b =
  let fpcm = content b 0 in
  let slen = 2 * Array.length fpcm * Array.length fpcm.(0) in
  let s = String.create slen in
    assert (Float_pcm.to_s16le fpcm 0 (Array.length fpcm.(0)) s 0 = slen);
    s

let duration () = Lazy.force duration
let size () = sot (Lazy.force size)
let position t = sot (position t)
let breaks t = List.map sot (breaks t)
let add_break t i = add_break t (tos i)
let set_breaks t l = set_breaks t (List.map tos l)

let set_metadata t i m = set_metadata t (tos i) m
let get_metadata t i = get_metadata t (tos i)
let get_all_metadata t =
  List.map (fun (x,y) -> sot x, y) (get_all_metadata t)
let set_all_metadata t l =
  set_all_metadata t (List.map (fun (x,y) -> tos x, y) l)

let blankify b off len =
  Float_pcm.blankify (content b off) off len

let multiply b off len c = Float_pcm.multiply (content b off) off len c

let add b1 off1 b2 off2 len =
  Float_pcm.add (content b1 off1) off1 (content b2 off2) off2 len

let substract b1 off1 b2 off2 len =
  Float_pcm.substract
    (content b1 off1) off1 (content b2 off2) off2 len

let rms b off len = Float_pcm.rms (content b off) off len