"""Reconstruct captured draw geometry for diagnosis, never native acceptance.

TASK117 has no composite-occupancy pass. This reader retains the originals,
enumerates every CPU/native raster exception, and labels every result diagnostic.
Native R7 capture and its GPU controls remain the acceptance source.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import claude_review_checks as checks
import terrain_contour_v3 as contour
import validate_terrain_acceptance_v2 as legacy


def rgba(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))


def matrix(t: list[float]) -> np.ndarray:
    return np.array([[t[0], t[2], t[4]], [t[1], t[3], t[5]], [0., 0., 1.]])


def transform(points: np.ndarray, m: np.ndarray) -> np.ndarray:
    return np.c_[points, np.ones(len(points))].dot(m.T)[:, :2]


def polygon_membership(points: np.ndarray, polygon: np.ndarray) -> np.ndarray:
    x, y = points.T
    inside = np.zeros(len(points), bool)
    for a, b in zip(polygon, np.roll(polygon, -1, axis=0)):
        if abs(b[1] - a[1]) < 1e-12:
            continue
        inside ^= ((a[1] > y) != (b[1] > y)) & (
            x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1]) + a[0])
    return inside


def segment_distance(points: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    v = b-a
    den = float(v@v)
    if den <= 1e-20:
        return np.linalg.norm(points-a, axis=1)
    f = np.clip((points-a)@v/den, 0, 1)
    return np.linalg.norm(points-a-f[:, None]*v, axis=1)


def geometry(leaf: dict, canvas: np.ndarray, shape: tuple[int, int],
             source: Path, textures: dict) -> tuple:
    """Pixel-centre polygon/nearest-atlas reconstruction; Line2D is diagnostic."""
    m = canvas @ matrix(leaf["global_transform"])
    kind = leaf["node_class"]
    alpha = float(leaf["self_modulate"][3])
    # The captured ancestor list includes the leaf itself exactly once.
    for ancestor in leaf["ancestor_canvas_inputs"]:
        alpha *= float(ancestor["modulate"][3])
    if kind == "Polygon2D":
        alpha *= float(leaf["primitive_color"][3])
        local = np.asarray(leaf["polygon"], float)
    elif kind == "Line2D":
        alpha *= float(leaf["default_color"][3])
        local = np.asarray(leaf["points"], float)
    elif kind == "Sprite2D":
        x, y, w, h = leaf["draw_bounds_local"]
        local = np.array([[x,y], [x+w,y], [x+w,y+h], [x,y+h]], float)
        if leaf["frame"] != 0 or leaf["region_enabled"]:
            raise ValueError("unsupported captured sprite frame/region")
    else:
        raise ValueError("unsupported captured leaf: " + kind)
    screen = transform(local, m)
    margin = float(leaf.get("width", 0)) * np.linalg.norm(m[:2,:2], ord=2)/2 + 2
    lo = np.maximum(0, np.floor(screen.min(axis=0)-margin).astype(int))
    hi = np.minimum([shape[1], shape[0]], np.ceil(screen.max(axis=0)+margin).astype(int))
    xx, yy = np.meshgrid(np.arange(lo[0],hi[0])+.5, np.arange(lo[1],hi[1])+.5)
    points = np.c_[xx.ravel(),yy.ravel()]
    local_points = transform(points,np.linalg.inv(m))
    boundary = np.full(len(points),np.inf)
    segments = list(zip(screen, np.roll(screen,-1,axis=0))) if kind != "Line2D" else list(zip(screen[:-1], screen[1:]))
    for a,b in segments:
        boundary = np.minimum(boundary,segment_distance(points,a,b))
    if kind == "Line2D":
        # Default Line2D joins and antialias edge interpolation are GPU-specific.
        # Only its boundary discrepancy is permitted, and every such pixel is listed.
        distance = np.full(len(points),np.inf)
        for a,b in zip(local[:-1],local[1:]):
            distance = np.minimum(distance,segment_distance(local_points,a,b))
        inside = distance <= float(leaf["width"])/2
        boundary = np.abs(boundary-float(leaf["width"])*np.linalg.norm(m[:2,:2],ord=2)/2)
    else:
        inside = polygon_membership(points,screen)
    values = np.where(inside,alpha,0.)
    texture = leaf.get("texture",{})
    texpath = texture.get("atlas_path") or texture.get("resource_path")
    if texpath:
        if texpath not in textures:
            p = source / texpath.removeprefix("res://")
            raw = p.read_bytes()
            digest = hashlib.sha256(raw).hexdigest()
            if texture.get("atlas_sha256") and texture["atlas_sha256"] != digest:
                raise ValueError("captured atlas source hash mismatch")
            textures[texpath] = (rgba(p), {"path":texpath.removeprefix("res://"),"bytes":len(raw),"sha256":digest})
        tex = textures[texpath][0]
        if kind == "Polygon2D":
            if not np.all(tex[...,3] == 255):
                raise ValueError("polygon texture is not fully opaque; UV reconstruction required")
        elif kind == "Line2D":
            raise ValueError("textured Line2D is unsupported")
        else:
            region = texture.get("region",[0,0,tex.shape[1],tex.shape[0]])
            x,y,w,h = leaf["draw_bounds_local"]
            u = (local_points[:,0]-x)/w
            v = (local_points[:,1]-y)/h
            if leaf["flip_h"]: u=1-u
            if leaf["flip_v"]: v=1-v
            sx=np.clip(np.floor(region[0]+u*region[2]).astype(int),0,tex.shape[1]-1)
            sy=np.clip(np.floor(region[1]+v*region[3]).astype(int),0,tex.shape[0]-1)
            values *= tex[sy,sx,3]/255.
            # A nearest alpha transition is also a raster boundary.
            grid=values.reshape(xx.shape)
            transition=np.zeros(xx.shape,bool)
            transition[:,1:] |= (grid[:,1:]>.5)!=(grid[:,:-1]>.5)
            transition[:,:-1] |= (grid[:,1:]>.5)!=(grid[:,:-1]>.5)
            transition[1:,:] |= (grid[1:,:]>.5)!=(grid[:-1,:]>.5)
            transition[:-1,:] |= (grid[1:,:]>.5)!=(grid[:-1,:]>.5)
            boundary=np.minimum(boundary,np.where(transition.ravel(),0.,np.inf))
    return (slice(lo[1],hi[1]),slice(lo[0],hi[0])), values.reshape(xx.shape), boundary.reshape(xx.shape)


def diagnose(folder: Path, source: Path) -> dict:
    capture=json.loads((folder/"capture-manifest.json").read_bytes())
    semantic=json.loads((folder/"semantic-sidecar-manifest.json").read_bytes())
    if hashlib.sha256((folder/"capture-manifest.json").read_bytes()).hexdigest() != semantic["capture_manifest_sha256"]:
        raise ValueError("capture/semantic manifest binding differs")
    records=semantic["frame"]["instance_tokens"]
    records_by_id={r["stable_id"]:r for r in records}
    names=("main","props","semantic_pair","semantic_coverage","grid","exclusions")
    for name in names:
        record=(semantic["frame"]["images"] if name.startswith("semantic_") else capture["images"])[name]
        raw=(folder/record["path"]).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=record["sha256"] or record["frame_id"]!=semantic["frame"]["frame_id"]:
            raise ValueError("raw image hash or frame binding differs: "+name)
        if "bytes" in record and record["bytes"]!=len(raw):
            raise ValueError("raw image byte count differs: "+name)
    images={name:rgba(folder/(name+".png")) for name in names}
    pair,coverage=images["semantic_pair"],images["semantic_coverage"]
    tokens=(pair[...,0].astype(np.uint32)<<16)|(pair[...,1].astype(np.uint32)<<8)|pair[...,2].astype(np.uint32)
    native_visible=(coverage[...,3]==255)&(coverage[...,0]>127)
    shape=coverage.shape[:2]
    opaque=np.zeros(shape,np.uint32)
    last=np.zeros(shape,np.uint32)
    last_alpha=np.zeros(shape,float)
    boundary_distance=np.full(shape,np.inf)
    textures={}; same_overlay=np.zeros(shape,bool); foreign_overlay=np.zeros(shape,bool)
    wall_geometry=np.zeros(shape,bool)
    true_tree_gaps=np.zeros(shape,bool)
    canvas=matrix(capture["viewports"]["main"]["final_transform"]) @ matrix(capture["viewports"]["main"]["canvas_transform"])
    for sid in semantic["frame"]["draw_order_stable_ids"]:
        record=records_by_id[sid]
        for leaf in record["draw_leaf_inputs"]:
            cut,alpha,bd=geometry(leaf,canvas,shape,source,textures)
            nonzero=alpha>0; solid=alpha>.5; semi=nonzero&~solid
            prior=opaque[cut]
            same_overlay[cut][solid]=False
            foreign_overlay[cut][solid]=False
            same_overlay[cut][semi & (prior==record["token"])]=True
            foreign_overlay[cut][semi & (prior!=record["token"]) & (prior!=0)]=True
            opaque[cut][solid]=record["token"]
            last[cut][nonzero]=record["token"]
            last_alpha[cut][nonzero]=alpha[nonzero]
            boundary_distance[cut]=np.minimum(boundary_distance[cut],bd)
            if sid=="wall@8.00,7.00": wall_geometry[cut] |= solid
            if record["type"]=="tree" and leaf["node_class"]=="Sprite2D":
                # Bound gaps by this one tree, never by unrelated distant trees.
                bounded=(np.maximum.accumulate(solid,axis=1)&np.maximum.accumulate(solid[:,::-1],axis=1)[:,::-1]
                         &np.maximum.accumulate(solid,axis=0)&np.maximum.accumulate(solid[::-1],axis=0)[::-1])
                true_tree_gaps[cut] |= bounded & (alpha==0)
    # First test CPU last-writer reconstruction against the frozen native image.
    cpu_visible=last_alpha>.5
    disagreements=(cpu_visible != native_visible) | (cpu_visible & native_visible & (last!=tokens))
    exceptions=[]
    for y,x in np.argwhere(disagreements):
        exceptions.append({"pixel_xy":[int(x),int(y)],"native_token":int(tokens[y,x]),
            "cpu_last_token":int(last[y,x]),"native_visible":bool(native_visible[y,x]),
            "cpu_last_alpha":float(last_alpha[y,x]),"distance_to_draw_boundary_px":float(boundary_distance[y,x]),
            "boundary_exception":bool(boundary_distance[y,x]<=1.25)})
    nonboundary=sum(not r["boundary_exception"] for r in exceptions)
    unaffected=~same_overlay & ~foreign_overlay
    occupancy_disagreements=unaffected & ((opaque!=0)!=native_visible)
    outside_exceptions=occupancy_disagreements & (boundary_distance>1.25)
    n6=[]
    for sid,(x,y) in [("pillar@1.00,4.00",(445,283)),("wall@4.00,1.00",(620,274))]:
        n6.append({"stable_id":sid,"pixel_xy":[x,y],"expected_token":records_by_id[sid]["token"],
                   "reconstructed_token":int(opaque[y,x]),"original_coverage_R":int(coverage[y,x,0]),
                   "status":"PASS" if opaque[y,x]==records_by_id[sid]["token"] else "FAIL"})
    tree_tokens=[r["token"] for r in records if r["type"]=="tree"]
    occluded=wall_geometry & np.isin(opaque,tree_tokens)
    n6.append({"stable_id":"wall@8.00,7.00","tree_occluded_pixels_retained":int(occluded.sum()),
               "status":"PASS" if occluded.any() else "FAIL"})
    # A source-alpha-zero gap remains empty after all instances have been drawn.
    empty=(opaque==0)&~native_visible&(coverage[...,0]<=127)
    holes=empty&true_tree_gaps
    n6.append({"check":"real_tree_empty_pixels","count":int(holes.sum()),
               "first_20_xy":[[int(x),int(y)] for y,x in np.argwhere(holes)[:20]],
               "status":"PASS" if holes.any() else "FAIL"})
    contexts=legacy.contexts(capture,images,pair,coverage,records)
    l=checks.lab(images["main"][...,:3])[...,0]
    blur=checks.lab(np.asarray(Image.fromarray(images["main"][...,:3]).filter(ImageFilter.GaussianBlur(2))))[...,0]
    rows=[]
    for c in contexts:
        r=c["record"]; group_tokens=[records_by_id[k]["token"] for k in c["members"]]
        own,group=contour.token_masks(opaque,r["token"],group_tokens)
        other_native=(coverage[...,3]==255)&~np.isin(tokens,group_tokens)
        other_occupied=(opaque!=0)&~np.isin(opaque,group_tokens)
        blocked=other_native|other_occupied|(images["exclusions"][...,3]>127)
        excluded=blocked|(images["grid"][...,3]>127)|((coverage[...,3]==255)&(coverage[...,0]<=127))
        rows.append({"stable_id":r["stable_id"],"type":r["type"],
                     "T1":contour.measure(l,own,group,excluded,blocked_pixels=blocked),
                     "T6":contour.measure(blur,own,group,excluded,blocked_pixels=blocked,squint=True)})
    inputs=[]
    for name in ["capture-manifest.json","semantic-sidecar-manifest.json"]+[x+".png" for x in names]:
        raw=(folder/name).read_bytes();inputs.append({"path":name,"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()})
    return {"schema":"terrain-occupancy-offline-diagnostic/1","diagnostic_only":True,
        "candidate_head":capture["candidate"]["head"],"frozen_TASK117_outputs_changed":False,
        "acceptance_use":"prohibited; native composite pass is required",
        "raster_method":"pixel-centre polygon; captured inverse transform and nearest atlas alpha; Line2D segment-distance approximation",
        "consistency":{"pixels":int(np.prod(shape)),"last_writer_native_disagreements":len(exceptions),
             "nonboundary_disagreements":nonboundary,"same_instance_translucent_overlay_pixels":int(same_overlay.sum()),
             "foreign_translucent_overlay_pixels":int(foreign_overlay.sum()),
             "unaffected_occupancy_disagreement_pixels":int(occupancy_disagreements.sum()),
             "unaffected_nonboundary_disagreements":int(outside_exceptions.sum()),
             "unaffected_occupancy_exceptions":[{"pixel_xy":[int(x),int(y)],
                  "native_visible":bool(native_visible[y,x]),"reconstructed_token":int(opaque[y,x]),
                  "distance_to_draw_boundary_px":float(boundary_distance[y,x])}
                  for y,x in np.argwhere(occupancy_disagreements)],
             "status":"PASS_WITH_LISTED_BOUNDARY_EXCEPTIONS" if not nonboundary and not outside_exceptions.any() else "FAIL",
             "exceptions":exceptions},"N6":n6,"instances":rows,
        "inputs":inputs,"textures":[row[1] for row in textures.values()]}


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder",type=Path);p.add_argument("--source-root",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True);a=p.parse_args()
    result=diagnose(a.folder,a.source_root)
    a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    print(json.dumps({"consistency":{k:v for k,v in result["consistency"].items() if k!="exceptions"},"N6":result["N6"]},ensure_ascii=False))
    return 0 if result["consistency"]["status"]!="FAIL" and all(x["status"]=="PASS" for x in result["N6"]) else 1


if __name__=="__main__":
    raise SystemExit(main())
