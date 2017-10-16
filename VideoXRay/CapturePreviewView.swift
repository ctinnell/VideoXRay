//
//  CapturePreviewView.swift
//  VideoXRay
//
//  Created by Tinnell, Clay on 10/16/17.
//  Copyright © 2017 Tinnell, Clay. All rights reserved.
//

import UIKit
import AVFoundation

class CapturePreviewView: UIView {

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

}
