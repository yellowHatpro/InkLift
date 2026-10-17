#!/usr/bin/env swift
// Generates the page background used inside exported .goodnotes files: a dot grid on a
// 455.04 x 588.45 pt page (the size the template's events index declares).
// usage: swift scripts/make-template-pdf.swift <out.pdf>
import Foundation
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.pdf")
var box = CGRect(x: 0, y: 0, width: 455.04, height: 588.45)
let data = NSMutableData()
let consumer = CGDataConsumer(data: data as CFMutableData)!
let info: [CFString: Any] = [kCGPDFContextCreator: "InkLift", kCGPDFContextTitle: "Dot grid"]
let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
ctx.beginPDFPage(nil)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fill(box)
ctx.setFillColor(CGColor(gray: 0.78, alpha: 1))
let step: CGFloat = 18.9   // 2/3 inch grid, like common dotted paper
var y = step
while y < box.height {
    var x = step
    while x < box.width {
        ctx.fillEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
        x += step
    }
    y += step
}
ctx.endPDFPage()
ctx.closePDF()
try! (data as Data).write(to: out)
print("wrote \(out.path) \(data.length) bytes")
