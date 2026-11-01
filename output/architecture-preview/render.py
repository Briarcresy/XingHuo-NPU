#!/usr/bin/env python3
"""Render paper-architecture JSON to SVG, PNG and editable draw.io.

Usage: python /tmp/xinghuo_render_paper.py spec.json output_prefix
Only the JSON spec is the source of truth. Rasterization uses system Python's
librsvg + cairo, independently of the Python that runs this script.
"""
import base64
import html
import json
import math
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

SVG_NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', SVG_NS)
DEFAULT_FONT = 'Arial, Helvetica, sans-serif'


def num(x):
    return format(float(x), '.6g')


def se(parent, tag, attrs=None, text=None):
    e = ET.SubElement(parent, '{%s}%s' % (SVG_NS, tag), {str(k): str(v) for k, v in (attrs or {}).items() if v is not None})
    if text is not None:
        e.text = str(text)
    return e


def dashval(d):
    if d is True:
        return '6 4'
    if not d:
        return None
    if isinstance(d, list):
        return ' '.join(map(num, d))
    return str(d)


def points(d):
    if d.get('points'):
        return [[float(p[0]), float(p[1])] for p in d['points']]
    if 'x1' in d:
        return [[d['x1'], d['y1']], [d['x2'], d['y2']]]
    return [[d.get('x', 0), d.get('y', 0)], [d.get('x', 0) + d.get('w', 0), d.get('y', 0) + d.get('h', 0)]]


def pd(pts):
    return 'M ' + ' L '.join('%s %s' % (num(x), num(y)) for x, y in pts)


def rectpath(x, y, w, h, r=0):
    r = min(float(r), float(w)/2, float(h)/2)
    if not r:
        return 'M %s %s h %s v %s h %s Z' % (num(x), num(y), num(w), num(h), num(-w))
    return ('M {a} {y} H {b} Q {c} {y} {c} {d} V {e} Q {c} {f} {b} {f} '
            'H {a} Q {x} {f} {x} {e} V {d} Q {x} {y} {a} {y} Z').format(
        a=num(x+r), b=num(x+w-r), c=num(x+w), d=num(y+r), e=num(y+h-r), f=num(y+h), x=num(x), y=num(y))


class Renderer:
    def __init__(self, spec):
        self.spec = spec
        self.paper = spec.get('paper', {})
        self.width = self.paper.get('width', 1400)
        self.height = self.paper.get('height', 900)
        self.font = self.paper.get('fonts', DEFAULT_FONT)
        if isinstance(self.font, dict):
            self.font = self.font.get('default', self.font.get('sans', DEFAULT_FONT))
        if isinstance(self.font, list):
            self.font = ', '.join(self.font)
        self.svg = ET.Element('{%s}svg' % SVG_NS, {'width': num(self.width), 'height': num(self.height), 'viewBox': '0 0 %s %s' % (num(self.width), num(self.height)), 'version': '1.1', 'font-family': self.font})
        se(self.svg, 'title', text=spec.get('title', 'Hardware architecture'))
        se(self.svg, 'desc', text=spec.get('description', 'Architecture diagram generated from a structured JSON specification.'))
        self.defs = se(self.svg, 'defs')
        self.markers = {}
        self.grid = {'margin': 36, 'cell_w': 220, 'cell_h': 90, 'gutter_x': 90, 'gutter_y': 70, **spec.get('grid', {})}
        self.boxes = {}
        for b in spec.get('blocks', []):
            g = self.grid
            self.boxes[b['id']] = (g.get('margin_x', g['margin']) + b['col'] * (g['cell_w'] + g['gutter_x']), g.get('margin_y', g['margin']) + b['row'] * (g['cell_h'] + g['gutter_y']), b.get('w', g['cell_w']), b.get('h', g['cell_h']))
        self.mx = ET.Element('mxfile', {'host': 'app.diagrams.net', 'type': 'device', 'version': '24.7.17'})
        diagram = ET.SubElement(self.mx, 'diagram', {'id': 'architecture', 'name': 'Architecture'})
        model = ET.SubElement(diagram, 'mxGraphModel', {'dx': num(self.width), 'dy': num(self.height), 'grid': '0', 'gridSize': '10', 'guides': '1', 'tooltips': '1', 'connect': '1', 'arrows': '1', 'fold': '1', 'page': '1', 'pageScale': '1', 'pageWidth': num(self.width), 'pageHeight': num(self.height), 'math': '0', 'shadow': '0', 'background': self.paper.get('background', '#FFFFFF')})
        self.mxroot = ET.SubElement(model, 'root')
        ET.SubElement(self.mxroot, 'mxCell', {'id': '0'})
        ET.SubElement(self.mxroot, 'mxCell', {'id': '1', 'parent': '0'})
        self.counter = 0

    def uid(self, prefix):
        self.counter += 1
        return '%s_%d' % (prefix, self.counter)

    def marker(self, color, start=False):
        key = (color, start)
        if key not in self.markers:
            mid = 'arrow_%d' % len(self.markers)
            m = se(self.defs, 'marker', {'id': mid, 'markerWidth': '8', 'markerHeight': '7', 'refX': '7', 'refY': '3.5', 'orient': 'auto-start-reverse', 'markerUnits': 'userSpaceOnUse', 'viewBox': '0 0 8 7', 'overflow': 'visible'})
            se(m, 'path', {'d': 'M 0 0 L 7 3.5 L 0 7 Z', 'fill': color, 'stroke': 'none'})
            self.markers[key] = mid
        return 'url(#%s)' % self.markers[key]

    def mx_vertex(self, oid, x, y, w, h, style, value=''):
        cell = ET.SubElement(self.mxroot, 'mxCell', {'id': oid, 'value': value, 'style': style, 'vertex': '1', 'parent': '1'})
        ET.SubElement(cell, 'mxGeometry', {'x': num(x), 'y': num(y), 'width': num(w), 'height': num(h), 'as': 'geometry'})
        return cell

    def box(self, oid, x, y, w, h, fill, stroke, radius=0, sw=1.5, dash=None, region=False):
        attrs = {'id': oid, 'x': num(x), 'y': num(y), 'width': num(w), 'height': num(h), 'rx': num(radius), 'fill': fill, 'stroke': stroke, 'stroke-width': num(sw), 'stroke-dasharray': dashval(dash)}
        se(self.svg, 'rect', attrs)
        style = 'shape=rectangle;whiteSpace=wrap;html=0;fillColor=%s;strokeColor=%s;strokeWidth=%s;rounded=%s;arcSize=%s;' % (fill, stroke, num(sw), '1' if radius else '0', num(200*radius/min(w,h)) if min(w,h) else '0')
        if dash:
            style += 'dashed=1;dashPattern=%s;' % dashval(dash)
        self.mx_vertex(oid, x, y, w, h, style)

    def text(self, t, prefix='label'):
        x, y = t['x'], t['y']
        size = t.get('size', 16)
        anchor = t.get('anchor', 'start')
        fill = t.get('fill', '#263544')
        family = t.get('family', self.font)
        weight = t.get('weight', 400)
        attrs = {'id': t.get('id', self.uid(prefix)), 'x': num(x), 'y': num(y), 'fill': fill, 'font-family': family, 'font-size': num(size), 'font-weight': str(weight), 'text-anchor': anchor, 'font-style': 'italic' if t.get('italic') else 'normal'}
        if t.get('halo'):
            halo = t['halo'] if isinstance(t['halo'], dict) else {}
            attrs.update({'stroke': halo.get('color', '#FFFFFF'), 'stroke-width': num(halo.get('width', 4)), 'paint-order': 'stroke', 'stroke-linejoin': 'round'})
        text = str(t.get('text', ''))
        el = se(self.svg, 'text', attrs)
        if '\n' in text:
            for i, line in enumerate(text.split('\n')):
                se(el, 'tspan', {'x': num(x), 'dy': '0' if not i else num(size*1.2)}, line)
        else:
            el.text = text
        maxline = max((len(z) for z in text.split('\n')), default=0)
        w = t.get('w', max(1, maxline*size*.67 + 4))
        h = t.get('h', size * (1.2*len(text.split('\n')) + .15))
        mx_x = x if anchor == 'start' else x-w/2 if anchor == 'middle' else x-w
        flags = (1 if (str(weight) in ('bold', 'semibold') or (str(weight).isdigit() and int(weight) >= 600)) else 0) + (2 if t.get('italic') else 0)
        style = 'text;html=0;strokeColor=none;fillColor=none;align=%s;verticalAlign=top;whiteSpace=wrap;overflow=visible;spacing=0;fontFamily=%s;fontSize=%s;fontColor=%s;fontStyle=%s;' % ({'start':'left','middle':'center','end':'right'}[anchor], family.split(',')[0].strip(), num(size), fill, flags)
        if t.get('halo'):
            style += 'labelBackgroundColor=#FFFFFF;'
        cell = self.mx_vertex('mx_' + attrs['id'], mx_x, y-size*.92, w, h, style, text)
        if t.get('_mx_parent'):
            parent = t['_mx_parent']
            parent_x, parent_y, _, _ = self.boxes[parent]
            cell.set('parent', parent)
            geometry = cell.find('mxGeometry')
            geometry.set('x', num(mx_x-parent_x))
            geometry.set('y', num(y-size*.92-parent_y))

    def edge_points(self, e):
        if e.get('route', {}).get('points'):
            return e['route']['points']
        x1,y1,w1,h1 = self.boxes[e['from']]
        x2,y2,w2,h2 = self.boxes[e['to']]
        if abs((x2+w2/2)-(x1+w1/2)) >= abs((y2+h2/2)-(y1+h1/2)):
            a=[x1+w1 if x2>x1 else x1, y1+h1/2]
            b=[x2 if x2>x1 else x2+w2, y2+h2/2]
            return [a,b] if a[1]==b[1] else [a,[(a[0]+b[0])/2,a[1]],[(a[0]+b[0])/2,b[1]],b]
        a=[x1+w1/2, y1+h1 if y2>y1 else y1]
        b=[x2+w2/2, y2 if y2>y1 else y2+h2]
        return [a,b] if a[0]==b[0] else [a,[a[0],(a[1]+b[1])/2],[b[0],(a[1]+b[1])/2],b]

    def mx_edge(self, oid, pts, color, sw, dash=None, arrow_start=False, arrow_end=True, source=None, target=None):
        style = 'edgeStyle=none;html=0;rounded=0;strokeColor=%s;strokeWidth=%s;startArrow=%s;endArrow=%s;startFill=1;endFill=1;startSize=7;endSize=7;' % (color, num(sw), 'block' if arrow_start else 'none', 'block' if arrow_end else 'none')
        if dash:
            style += 'dashed=1;dashPattern=%s;' % dashval(dash)
        if source:
            x,y,w,h=self.boxes[source]
            style += 'exitX=%s;exitY=%s;exitDx=0;exitDy=0;exitPerimeter=0;' % (num((pts[0][0]-x)/w), num((pts[0][1]-y)/h))
        if target:
            x,y,w,h=self.boxes[target]
            style += 'entryX=%s;entryY=%s;entryDx=0;entryDy=0;entryPerimeter=0;' % (num((pts[-1][0]-x)/w), num((pts[-1][1]-y)/h))
        attrs={'id':oid,'value':'','style':style,'edge':'1','parent':'1'}
        if source: attrs['source']=source
        if target: attrs['target']=target
        cell=ET.SubElement(self.mxroot,'mxCell',attrs)
        geo=ET.SubElement(cell,'mxGeometry',{'relative':'1','as':'geometry'})
        if not source: ET.SubElement(geo,'mxPoint',{'x':num(pts[0][0]),'y':num(pts[0][1]),'as':'sourcePoint'})
        if not target: ET.SubElement(geo,'mxPoint',{'x':num(pts[-1][0]),'y':num(pts[-1][1]),'as':'targetPoint'})
        if len(pts)>2:
            arr=ET.SubElement(geo,'Array',{'as':'points'})
            for x,y in pts[1:-1]: ET.SubElement(arr,'mxPoint',{'x':num(x),'y':num(y)})

    def edge(self, e, idx):
        p=e.get('paper',{})
        color=p.get('color', '#334A5F')
        sw=p.get('stroke_width', 1.7)
        pts=self.edge_points(e)
        oid=e.get('id', 'edge_%s__%s' % (e['from'],e['to']))
        attrs={'id':oid,'d':pd(pts),'fill':'none','stroke':color,'stroke-width':num(sw),'stroke-linecap':'butt','stroke-linejoin':'round','stroke-dasharray':dashval(p.get('dash'))}
        if p.get('arrow_end',True): attrs['marker-end']=self.marker(color)
        if p.get('arrow_start'): attrs['marker-start']=self.marker(color, True)
        se(self.svg,'path',attrs)
        self.mx_edge(oid,pts,color,sw,p.get('dash'),p.get('arrow_start',False),p.get('arrow_end',True),e['from'],e['to'])
        return p.get('labels',[])

    def decoration(self,d):
        typ=d['type']; oid=d.get('id',self.uid('decoration'))
        fill=d.get('fill','none'); stroke=d.get('stroke','none'); sw=d.get('stroke_width',1)
        attrs={'id':oid,'fill':fill,'stroke':stroke,'stroke-width':num(sw),'stroke-dasharray':dashval(d.get('dash'))}
        if d.get('arrow'): attrs['marker-end']=self.marker(stroke)
        if typ=='rect':
            x,y,w,h=d['x'],d['y'],d['w'],d['h']; r=d.get('radius',0)
            attrs['d']=rectpath(x,y,w,h,r)
            se(self.svg,'path',attrs)
            style='shape=rectangle;html=0;fillColor=%s;strokeColor=%s;strokeWidth=%s;rounded=%s;arcSize=%s;' % (fill,stroke,num(sw),'1' if r else '0',num(200*r/min(w,h)) if min(w,h) else '0')
            if d.get('dash'): style+='dashed=1;dashPattern=%s;' % dashval(d['dash'])
            self.mx_vertex(oid,x,y,w,h,style)
        elif typ=='circle':
            cx,cy,r=d['cx'],d['cy'],d['r']
            attrs.update({'cx':num(cx),'cy':num(cy),'r':num(r)})
            se(self.svg,'circle',attrs)
            self.mx_vertex(oid,cx-r,cy-r,2*r,2*r,'shape=ellipse;html=0;fillColor=%s;strokeColor=%s;strokeWidth=%s;' % (fill,stroke,num(sw)))
        elif typ in ('line','path'):
            pts=points(d)
            attrs['d']=d.get('d',pd(pts))
            if d.get('closed'): attrs['d']+=' Z'
            se(self.svg,'path',attrs)
            if 'd' not in d and fill=='none' and not d.get('closed'):
                self.mx_edge(oid,pts,stroke,sw,d.get('dash'),False,bool(d.get('arrow')))
            else:
                self.mx_stencil_path(oid,attrs['d'],fill,stroke,sw,d.get('dash'))
        else:
            raise ValueError('Unsupported decoration: '+typ)

    def mx_stencil_path(self,oid,d,fill,stroke,sw,dash):
        # A native draw.io stencil preserves arbitrary SVG-like editable vectors.
        # SVG path M/L/H/V/Q/C/Z (absolute or relative) maps to stencil operations.
        toks=re.findall(r'[MLHVQCZmlhvqcz]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',d)
        commands=[]; vertices=[]; i=0; cmd=None; x=y=0; sx=sy=0
        while i<len(toks):
            if toks[i].isalpha(): cmd=toks[i]; i+=1
            u=cmd.upper(); rel=cmd.islower()
            if u=='Z': commands.append(('close',{})); x,y=sx,sy; cmd=None; continue
            n={'M':2,'L':2,'H':1,'V':1,'Q':4,'C':6}[u]
            vals=list(map(float,toks[i:i+n])); i+=n
            if u in ('M','L'):
                nx,ny=vals; nx+=x if rel else 0; ny+=y if rel else 0
                commands.append(('move' if u=='M' else 'line',{'x':nx,'y':ny})); vertices.append((nx,ny)); x,y=nx,ny
                if u=='M': sx,sy=x,y; cmd='l' if rel else 'L'
            elif u in ('H','V'):
                if u=='H': x=vals[0]+(x if rel else 0)
                else: y=vals[0]+(y if rel else 0)
                commands.append(('line',{'x':x,'y':y})); vertices.append((x,y))
            else:
                coords=[]
                for j in range(0,n,2): coords.append((vals[j]+(x if rel else 0), vals[j+1]+(y if rel else 0)))
                a={}
                for j,(xx,yy) in enumerate(coords,1): a['x'+str(j)]=xx; a['y'+str(j)]=yy
                commands.append(('quad' if u=='Q' else 'curve',a)); vertices.extend(coords); x,y=coords[-1]
        minx=min(p[0] for p in vertices); miny=min(p[1] for p in vertices)
        w=max(1,max(p[0] for p in vertices)-minx); h=max(1,max(p[1] for p in vertices)-miny)
        shape=ET.Element('shape',{'name':oid,'w':num(w),'h':num(h),'aspect':'variable','strokewidth':'inherit'})
        fg=ET.SubElement(shape,'foreground'); path=ET.SubElement(fg,'path')
        for tag,attrs in commands:
            ET.SubElement(path,tag,{k:num(v-(minx if k.startswith('x') else miny)) for k,v in attrs.items()})
        ET.SubElement(fg,'fillstroke' if fill!='none' else 'stroke')
        raw=ET.tostring(shape,encoding='utf-8')
        compressor=zlib.compressobj(level=9,wbits=-15)
        encoded=base64.b64encode(compressor.compress(raw)+compressor.flush()).decode('ascii')
        style='shape=stencil(%s);fillColor=%s;strokeColor=%s;strokeWidth=%s;' % (encoded,fill,stroke,num(sw))
        if dash: style+='dashed=1;dashPattern=%s;' % dashval(dash)
        self.mx_vertex(oid,minx,miny,w,h,style)

    def render(self):
        # Background is a path so geometry validators do not classify it as a block.
        se(self.svg,'path',{'id':'canvas_background','d':rectpath(0,0,self.width,self.height),'fill':self.paper.get('background','#FFFFFF'),'stroke':'none'})
        deferred=[]
        for r in self.paper.get('regions',[]):
            oid=r['id'] if r['id'].startswith('group_') else 'group_'+r['id']
            self.box(oid,r['x'],r['y'],r['w'],r['h'],r.get('fill','#FFFFFF'),r.get('stroke','#B5C1CB'),r.get('radius',0),r.get('stroke_width',1.2),r.get('dash'),True)
            deferred.extend(r.get('labels',[]))
        for i,e in enumerate(self.spec.get('edges',[])): deferred.extend(self.edge(e,i))
        for b in self.spec.get('blocks',[]):
            p=b.get('paper',{}); domain=self.spec.get('domains',{}).get(b.get('domain'),{})
            x,y,w,h=self.boxes[b['id']]
            self.box(b['id'],x,y,w,h,p.get('fill',domain.get('color','#F3F5F7')),p.get('stroke',domain.get('border','#4F6478')),p.get('radius',3),p.get('stroke_width',1.5),p.get('dash'))
            block_text_start = len(deferred)
            if 'texts' in p:
                deferred.extend(p['texts'])
            elif not p.get('hide_label'):
                lines=b.get('lines')
                if lines:
                    for i,line in enumerate(lines): deferred.append({'x':x+w/2,'y':y+h/2+(i-(len(lines)-1)/2)*21+6,'text':line,'anchor':'middle','size':17,'weight':600 if i==0 else 400})
                else:
                    deferred.append({'x':x+w/2,'y':y+h/2+(0 if b.get('sublabel') else 6),'text':b.get('label',b['id']),'anchor':'middle','size':18,'weight':600})
                    if b.get('sublabel'): deferred.append({'x':x+w/2,'y':y+h/2+23,'text':b['sublabel'],'anchor':'middle','size':13,'fill':'#526171'})
            deferred[block_text_start:] = [dict(t, _mx_parent=b['id']) for t in deferred[block_text_start:]]
        for d in self.paper.get('decorations',[]): self.decoration(d)
        for t in deferred+self.paper.get('texts',[]): self.text(t)
        return self.svg,self.mx


def rasterize(svgpath,pngpath,width,height):
    script='''import sys\nimport gi\ngi.require_version("Rsvg", "2.0")\nfrom gi.repository import Rsvg\nimport cairo\nsvg, png, width, height = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])\nhandle = Rsvg.Handle.new_from_file(svg)\nsurface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)\ncontext = cairo.Context(surface)\nrect = Rsvg.Rectangle()\nrect.x = 0; rect.y = 0; rect.width = width; rect.height = height\nhandle.render_document(context, rect)\nsurface.write_to_png(png)\n'''
    subprocess.run(['/usr/bin/python3','-c',script,str(svgpath),str(pngpath),str(width),str(height)],check=True)


def main():
    if len(sys.argv)!=3:
        raise SystemExit(__doc__)
    specpath=Path(sys.argv[1]); prefix=Path(sys.argv[2])
    spec=json.loads(specpath.read_text(encoding='utf-8'))
    prefix.parent.mkdir(parents=True,exist_ok=True)
    renderer=Renderer(spec); svg,mx=renderer.render()
    svgpath=Path(str(prefix)+'.svg'); mxpath=Path(str(prefix)+'.drawio')
    ET.indent(svg); ET.indent(mx)
    ET.ElementTree(svg).write(svgpath,encoding='utf-8',xml_declaration=True)
    ET.ElementTree(mx).write(mxpath,encoding='utf-8',xml_declaration=True)
    rasterize(svgpath,Path(str(prefix)+'.png'),round(renderer.width*2),round(renderer.height*2))
    rasterize(svgpath,Path(str(prefix)+'-readme.png'),900,round(renderer.height*900/renderer.width))
    print(json.dumps({'svg':str(svgpath),'png':str(prefix)+'.png','readme_png':str(prefix)+'-readme.png','drawio':str(mxpath),'canvas':[renderer.width,renderer.height]},ensure_ascii=False))


if __name__=='__main__':
    main()
