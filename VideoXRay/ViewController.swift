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
    let videoOutput = AVCaptureVideoDataOutput()
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Stop", style: .plain, target: self, action: #selector(stopRecording))
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
        try configureDeviceOutput()
        try configureMovieWriting()
        session.commitConfiguration()
    }
    
    func configureDeviceOutput() throws {
        if session.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
            session.addOutput(videoOutput)
            
            for connection in videoOutput.connections {
                for port in connection.inputPorts {
                    if port.mediaType == .video {
                        connection.videoOrientation = .portrait
                    }
                }
            }
        }
        else {
            throw SetupError.videoOutputFailed
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func configureMovieWriting() throws {
        movieURL = getDocumentsDirectory().appendingPathComponent("movie.mov")
        let fm = FileManager.default
        
        if fm.fileExists(atPath: movieURL.path) {
            print("movieURL: \(movieURL)")
            try fm.removeItem(at: movieURL)
        }
        
        assetWriter = try AVAssetWriter(url: movieURL, fileType: .mp4)
        
        let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = true
        
        if assetWriter.canAdd(writerInput) {
            assetWriter.add(writerInput)
        }
    }
    
    @objc func stopRecording() {
        recordingActive = false
        assetWriter?.finishWriting {
            if (self.assetWriter?.status == .failed) {
                print("Failed to save")
            }
            else {
                print("Succeeded saving")
            }
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recordingActive else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) == true else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if assetWriter.status == .unknown {
            //we'll use this later
            startTime = currentTime
            
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: currentTime)
            
            return
        }
        
        if assetWriter.status == .failed {
            return
        }
        
        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }
        
        guard readyToAnalyze else { return }
        readyToAnalyze = false
        
        DispatchQueue.global().async {
            let inputSize = CGSize(width: 227.0, height: 227.0)
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            
            guard let resizedPixelBuffer = image.pixelBuffer(at: inputSize, context: self.context) else { return }
            
            let prediction = try? self.model.prediction(image: resizedPixelBuffer)
            
            let predictionName = prediction?.classLabel ?? "Unknown"
            
            print("\(self.predictions.count): \(predictionName)")
            let timeDiff = currentTime - self.startTime
            
            self.predictions.append((timeDiff, predictionName))
            
            self.readyToAnalyze = true
        }
    }
}

extension CIImage {
    
    func pixelBuffer(at size: CGSize, context: CIContext) -> CVPixelBuffer? {
        
        //1 - create a dictionary requesting Core Graphics compatibility
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        //2 - create a pixel buffer at the size our model needs
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attributes, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }
        
        //3 - calculate how much we need to scale down our image
        let scale = size.width / self.extent.size.width
        
        //4 - create a new scaled-down image using the scale we just calculated
        let resizedImage = self.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        //5 - calculate a cropping rectangle and apply it immediately
        let width = resizedImage.extent.width
        let height = resizedImage.extent.height
        let yOffset = (CGFloat(height) - size.height) / 2.0
        let rect = CGRect(x: (CGFloat(width) - size.width) / 2.0, y: yOffset, width: size.width, height: size.height)
        let croppedImage = resizedImage.cropped(to: rect)
        
        //6 - move the cropped image down so that its centered
        let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: 0, y: -yOffset))
        
        //7 - render the CIImage to our CVPixelBuffer and return it
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        context.render(translatedImage, to: pixelBuffer!)
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
}


