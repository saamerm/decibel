//
//  ViewController.swift
//  Decibel
//
//  Created by Peter Reinhardt on 8/13/16.
//  Copyright © 2016 Peter Reinhardt. All rights reserved.
//

import UIKit
import AVFoundation
import UserNotifications
/*
 NOTE: PLEASE PUT YOUR DATADOG KEY BELOW
 */
let DATADOG_KEY = "6e3643ad99efb9052fcc6d461fb718c6"
/*
 NOTE: PLEASE PUT YOUR DATADOG KEY ABOVE
 */

class ViewController: UIViewController {

    var timer: DispatchSourceTimer?

    @IBOutlet weak var AverageValueLabel: UILabel!
    @IBOutlet weak var PeakValueLabel: UILabel!
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let userNotificationCenter = UNUserNotificationCenter.current()
        let authOptions = UNAuthorizationOptions.init(arrayLiteral: .alert, .badge, .sound)
        userNotificationCenter.requestAuthorization(options: authOptions) { (success, error) in
            if let error = error {
                print("Error: ", error)
            }
        }
        
        // Do any additional setup after loading the view.
        if DATADOG_KEY == "YOUR_KEY_HERE" {
            fatalError("You must update your datadog key to use Decibel")
        }
        guard let url = directoryURL() else {
            print("Unable to find a init directoryURL")
            return
        }
        
        let recordSettings = [
            AVSampleRateKey : NSNumber(value: Float(44100.0) as Float),
            AVFormatIDKey : NSNumber(value: Int32(kAudioFormatMPEG4AAC) as Int32),
            AVNumberOfChannelsKey : NSNumber(value: 1 as Int32),
            AVEncoderAudioQualityKey : NSNumber(value: Int32(AVAudioQuality.medium.rawValue) as Int32),
        ]

        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord)
            let audioRecorder = try AVAudioRecorder(url: url, settings: recordSettings)
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            try audioSession.setActive(true)
            audioRecorder.isMeteringEnabled = true
            recordForever(audioRecorder: audioRecorder)
        } catch let err {
            print("Unable start recording", err)
        }
    }
    
    override func didReceiveMemoryWarning() {
         super.didReceiveMemoryWarning()
         // Dispose of any resources that can be recreated.
    }
    
    func directoryURL() -> URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as URL
        let soundURL = documentDirectory.appendingPathComponent("sound.m4a")
        return soundURL
    }
    
    func recordForever(audioRecorder: AVAudioRecorder) {
        let queue = DispatchQueue(label: "io.segment.decibel", attributes: .concurrent)
        timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        timer?.scheduleRepeating(deadline: .now(), interval: .milliseconds(1000), leeway: .milliseconds(100))
        timer?.setEventHandler { [weak self] in
            audioRecorder.updateMeters()

             // NOTE: seems to be the approx correction to get real decibels
            let correction: Float = 100
            let average = audioRecorder.averagePower(forChannel: 0) + correction
            let peak = audioRecorder.peakPower(forChannel: 0) + correction

            // Uncomment this if you want to work with data dog
            //            self?.recordDatapoint(average: average, peak: peak)

            if (peak > 80)
            {
                let content = UNMutableNotificationContent()
                content.title = "Noise alert notification"
                content.body = "The noise is loud at " + String(describing: peak)

                // Configure the recurring date.
                var dateComponents = DateComponents()

                let date = Date()
                let calendar = Calendar.current
                dateComponents.calendar = calendar
                dateComponents.hour = calendar.component(.hour, from: date)
                dateComponents.minute = calendar.component(.minute, from: date)
                dateComponents.second = calendar.component(.second, from: date) + 1
                
                // Create the trigger as a repeating event.
                let trigger = UNCalendarNotificationTrigger(
                         dateMatching: dateComponents, repeats: false)

                let uuidString = UUID().uuidString
                let request = UNNotificationRequest(identifier: uuidString,
                            content: content, trigger: trigger)

                // Schedule the request with the system.
                let notificationCenter = UNUserNotificationCenter.current()

                notificationCenter.add(request) { (error) in
                   if error != nil {
                      // Handle any errors.
                   }
                }
            }
            DispatchQueue.main.async {
                self?.AverageValueLabel.text = String(describing: average)
                self?.PeakValueLabel.text =  String(describing: peak)
            }
        }
        timer?.resume()
    }
    
    
    func recordDatapoint(average: Float, peak: Float) {

        // Send a single datapoint to DataDog
        let datadogUrlString = "https://app.datadoghq.com/api/v1/series?api_key=\(DATADOG_KEY)"
        
        let deviceName = UIDevice.current.name
        let timestamp = (NSInteger)(Date().timeIntervalSince1970)
        let body = [
            "series": [
                ["metric": "office.dblevel.average", "host": deviceName, "points": [ [timestamp, average] ] ],
                ["metric": "office.dblevel.peak", "host": deviceName, "points":[ [timestamp, peak] ] ],
            ]
        ]
        
        guard let datadogUrl = URL(string: datadogUrlString),
            let httpBody = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            print("Bad URL or body")
            return
        }
        print("Will send request to \(datadogUrl)", body)
        
        let request = NSMutableURLRequest(url: datadogUrl)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request as URLRequest) { data, response, error in
            if let error = error {
                print("error=\(error)")
                return
            }
            if let data = data {
                let responseString = String(data: data, encoding: String.Encoding.utf8)
                print("responseString = \(responseString)")
                return
            }
            print("Neither error nor data was provided")
        }
        task.resume()
    }


}

