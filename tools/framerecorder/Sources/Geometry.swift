import Foundation
import CoreGraphics

enum RegionGeometry {
    static let minimum: CGFloat = 40
    static func normalized(_ a: CGPoint, _ b: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y)).intersection(bounds)
    }
    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, bounds: CGRect) -> CGRect {
        var r=rect
        r.origin.x=min(max(bounds.minX,r.minX+dx),bounds.maxX-r.width)
        r.origin.y=min(max(bounds.minY,r.minY+dy),bounds.maxY-r.height)
        return r
    }
    static func resized(_ r: CGRect, handle: Int, point: CGPoint, bounds: CGRect) -> CGRect {
        var x1=r.minX, x2=r.maxX, y1=r.minY, y2=r.maxY
        let x=min(max(point.x,bounds.minX),bounds.maxX), y=min(max(point.y,bounds.minY),bounds.maxY)
        if [0,3,6].contains(handle) { x1=min(x,x2-minimum) }
        if [2,5,8].contains(handle) { x2=max(x,x1+minimum) }
        if [0,1,2].contains(handle) { y1=min(y,y2-minimum) }
        if [6,7,8].contains(handle) { y2=max(y,y1+minimum) }
        return CGRect(x:x1,y:y1,width:x2-x1,height:y2-y1)
    }
    static func captureRect(_ local: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x:local.minX,y:screenHeight-local.maxY,width:local.width,height:local.height)
    }
    static func pixelSize(_ r: CGRect, scale: CGFloat) -> (Int,Int) {
        (max(2,Int((r.width*scale).rounded())/2*2),max(2,Int((r.height*scale).rounded())/2*2))
    }
}
