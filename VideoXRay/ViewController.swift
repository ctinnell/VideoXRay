//
//  ViewController.swift
//  VideoXRay
//
//  Created by Tinnell, Clay on 10/16/17.
//  Copyright © 2017 Tinnell, Clay. All rights reserved.
//

import UIKit
import AVKit

enum SetupError: Error {
    case noVideoDevice, videoInputFailed, videoOutputFailed
}

class ViewController: UIViewController {

    let session = AVCaptureSession()
    let viewOutput = AVCaptureVideoDataOutput()
    var capturePreview = CapturePreviewView()
    var assetWriter: AVAssetWriter!
    var writerInput: AVAssetWriterInput!
    let model = SqueezeNet()
    let context = CIContext()
    var recordingActive = false
    var readyToAnalyze = true
    var startTime: CMTime!
    var movieURL: URL!
    var predictions = [(time: CMTime, prediction: String)]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        capturePreview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(capturePreview)
        capturePreview.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        capturePreview.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        capturePreview.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        capturePreview.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        (capturePreview.layer as! AVCaptureVideoPreviewLayer).session = session
        do {
            try configureSession()
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Record", style: .plain, target: self, action: #selector(startRecording))
        } catch {
            print("Session Configuration Failed!")
        }

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @objc func startRecording() {
        recordingActive = true
        session.startRunning()
    }
    
    func configureVideoDeviceInput() throws {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            throw SetupError.noVideoDevice
        }
        
        let videoDeviceInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        
        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
        }
        else {
            throw SetupError.videoInputFailed
        }
    }
    
    func configureSession() throws {
        session.beginConfiguration()
        try configureVideoDeviceInput()
        session.commitConfiguration()
    }
}

