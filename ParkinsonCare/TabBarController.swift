//
//  TabBarController.swift
//  ParkinsonCare
//
//  Created by Matthew Hormis on 4/30/19.
//  Copyright © 2019 BE428. All rights reserved.
//

import UIKit
import CareKit
import CoreMotion


class TabBarController: UITabBarController {
    lazy var carePlanStore: OCKCarePlanStore = {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let url = urls[0].appendingPathComponent("carePlanStore")
        
        if !fileManager.fileExists(atPath: url.path) {
            try! fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        
        // lazy var carePlanStore
        
        let store = OCKCarePlanStore(persistenceDirectoryURL: url)
        store.delegate = self
        return store
        
        //return OCKCarePlanStore(persistenceDirectoryURL: url)
    }()
    
    let activityStartDate = DateComponents(year: 2019, month: 1, day: 1)
    let calendar = Calendar(identifier: .gregorian)
    lazy var monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    
    var insights: OCKInsightsViewController!
    var insightItems = [OCKInsightItem]() {
        didSet {
            insights.items = insightItems
        }
    }
    
    var contacts = [OCKContact]()
    
    let motionManager = CMMotionManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
            addActivities()
            addContacts()
        
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.01
            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
                print(data)
            }
        }
        // Do any additional setup after loading the view.
        
        let careCard = OCKCareCardViewController(carePlanStore: carePlanStore)
        careCard.title = "Care"
        let symptomTracker = OCKSymptomTrackerViewController(carePlanStore: carePlanStore)
        symptomTracker.title = "Measurements"
        symptomTracker.delegate = self
        
        insights = OCKInsightsViewController(insightItems: insightItems)
        insights.title = "Insights"
        updateInsights()
        
        let connect = OCKConnectViewController(contacts: contacts)
        connect.title = "Connect"
        
        connect.delegate = self
        
        viewControllers = [
            UINavigationController(rootViewController: careCard),
            UINavigationController(rootViewController: symptomTracker),
            UINavigationController(rootViewController: insights),
            UINavigationController(rootViewController: connect)
        ]
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func interventions() -> [OCKCarePlanActivity] {
        let waterSchedule = OCKCareSchedule.dailySchedule(withStartDate: activityStartDate, occurrencesPerDay: 6)
        let waterIntervention = OCKCarePlanActivity.intervention(withIdentifier: "water", groupIdentifier: nil, title: "Tremor Levels", text: "Shaking of hand at 3 - 6Hz", tintColor: .blue, instructions: nil, imageURL: nil, schedule: waterSchedule, userInfo: nil, optional: true)
        
        let exerciseSchedule = OCKCareSchedule.dailySchedule(withStartDate: activityStartDate, occurrencesPerDay: 1, daysToSkip: 1, endDate: nil)
        
        let exerciseIntervention = OCKCarePlanActivity.intervention(withIdentifier: "exercise", groupIdentifier: nil, title: "Exercise", text: "30 min", tintColor: .orange, instructions: nil, imageURL: nil, schedule: exerciseSchedule, userInfo: nil, optional: true)
        
        return [waterIntervention, exerciseIntervention]
    }
    
    func assessments() -> [OCKCarePlanActivity] {
        let oncePerDaySchedule = OCKCareSchedule.dailySchedule(withStartDate: activityStartDate, occurrencesPerDay: 1)
        
        let sleepAssessment = OCKCarePlanActivity.assessment(withIdentifier: "sleep", groupIdentifier: nil, title: "Tremors", text: nil, tintColor: .purple, resultResettable: true, schedule: oncePerDaySchedule, userInfo: nil, optional: true)
        
        let weightAssessment = OCKCarePlanActivity.assessment(withIdentifier: "weight", groupIdentifier: nil, title: "Weight", text: nil, tintColor: .brown, resultResettable: true, schedule: oncePerDaySchedule, userInfo: nil, optional: true)
        return [sleepAssessment, weightAssessment]
    }

    func addActivities() {
        func addActivities() {
            for activity in interventions() + assessments() {
                self.carePlanStore.add(activity) { (_, error) in
                    guard let error = error else { return }
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    func updateInsights() {
        self.insightItems = []
        
        var sleep = [DateComponents: Int]()
        var interventionCompletion = [DateComponents: Int]()
        let activitiesDispatchGroup = DispatchGroup()
        
        activitiesDispatchGroup.enter()
        fetchSleep { sleepDict in
            sleep = sleepDict
            activitiesDispatchGroup.leave()
        }
        
        activitiesDispatchGroup.enter()
        fetchInterventionCompletion { interventionCompletionDict in
            interventionCompletion = interventionCompletionDict
            activitiesDispatchGroup.leave()
        }
        activitiesDispatchGroup.notify(queue: .main) {
            if let sleepMessage = self.sleepMessage(sleep: sleep) {
                self.insightItems.append(sleepMessage)
            }
            self.insightItems.append(self.interventionBarChart(interventionCompletion: interventionCompletion, sleep: sleep))
        }
    }
    
    var today: Date {
        return Date()
    }
    
    func fetchSleep(completion: @escaping ([DateComponents: Int]) -> ()) {
        var sleep = [DateComponents: Int]()
        
        let sleepStartDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -7), to: today)!)
        let sleepEndDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -1), to: today)!)
        
        carePlanStore.activity(forIdentifier: "sleep") { [unowned self] (_, activity, error) in
            if let error = error {
                print(error.localizedDescription)
            }
            guard let sleepAssessment = activity else { return }
            self.carePlanStore.enumerateEvents(of: sleepAssessment, startDate: sleepStartDate, endDate: sleepEndDate, handler: { (event, _) in
                guard let event = event else { return }
                if let result = event.result {
                    sleep[event.date] = Int(result.valueString)!
                } else {
                    sleep[event.date] = 0
                }
            }, completion: { (_, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
                completion(sleep)
            })
        }
    }
    
    func fetchInterventionCompletion(completion: @escaping ([DateComponents: Int]) -> ()) {
        var interventionCompletion = [DateComponents: Int]()
        
        let interventionStartDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -7), to: today)!)
        let interventionEndDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -1), to: today)!)
        
        carePlanStore.dailyCompletionStatus(with: .intervention, startDate: interventionStartDate, endDate: interventionEndDate, handler: { (date, completed, total) in
            interventionCompletion[date] = lround((Double(completed) / Double(total)) * 100)
        }, completion: { (_, error) in
            if let error = error {
                print(error.localizedDescription)
            }
            completion(interventionCompletion)
        })
    }
    
    func sleepMessage(sleep: [DateComponents: Int]) -> OCKMessageItem? {
        let sleepAverage = Double(sleep.values.reduce(0) { $0 + $1 }) / Double(sleep.count)
        //let sleepAverageInt = lround(sleepAverage)
        if sleepAverage < 3 {
            let averageAlert = OCKMessageItem(title: "Sleep More", text: "You have not experienced many tremors this week, you are good!", tintColor: .purple, messageType: .alert)
            return averageAlert
        } else if sleepAverage > 7.5 {
            let averageTip = OCKMessageItem(title: "Maintain Sleep Habits", text: "You are experiencing excessive Tremors. You might want to see a professional regarding this", tintColor: .purple, messageType: .tip)
            return averageTip
        }
        return nil
    }
    
    func interventionBarChart(interventionCompletion: [DateComponents: Int], sleep: [DateComponents: Int]) -> OCKBarChart {
        let sortedDates = interventionCompletion.keys.sorted() {
            calendar.dateComponents([.second], from: $0, to: $1).second! > 0
        }
        let formattedDates = sortedDates.map {
            monthDayFormatter.string(from: calendar.date(from: $0)!)
        }
        let interventionValues = sortedDates.map { interventionCompletion[$0]! }
        let interventionSeries = OCKBarSeries(title: "Care Completion", values: interventionValues as [NSNumber], valueLabels: interventionValues.map { "\($0)%" }, tintColor: .red)
        let sleepNumbers = sortedDates.map { sleep[$0]! }
        let sleepValues: [Double]
        if sleep.values.max()! > 0 {
            let singleHourWidth = 100.0 / Double(sleep.values.max()!)
            sleepValues = sleepNumbers.map { singleHourWidth * Double($0) }
        } else {
            sleepValues = sleepNumbers.map { _ in 0 }
        }
        let sleepSeries = OCKBarSeries(title: "Tremors", values: sleepValues as [NSNumber], valueLabels: sleepNumbers.map { "\($0)" }, tintColor: .purple)
        let interventionBarChart = OCKBarChart(title: "Care Completion of Tremors", text: "See how completing your care plan affects your Tremors.", tintColor: nil, axisTitles: formattedDates, axisSubtitles: nil, dataSeries: [interventionSeries, sleepSeries], minimumScaleRangeValue: 0, maximumScaleRangeValue: 100)
        return interventionBarChart
    }
    
    func addContacts() {
        let doctor = OCKContact(contactType: .careTeam, name: "Dr. Nicte I. Mejia", relation: "Doctor", contactInfoItems: [.phone("(617) 726-5532"), .sms("(617) 726-5532"), .email("t.matt97@yahoo.com")], tintColor: nil, monogram: nil, image: nil)
        let apda = OCKContact(contactType: .personal, name: "American Parkinsons Disease Association", relation: "Massachusetts Chapter", contactInfoItems: [.phone("(888) 555-2346"), .email("apdama@apdaparkinson.org")], tintColor: nil, monogram: nil, image: nil)
        
        contacts = [doctor, apda]
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

extension TabBarController: OCKSymptomTrackerViewControllerDelegate {
    func symptomTrackerViewController(_ viewController: OCKSymptomTrackerViewController, didSelectRowWithAssessmentEvent assessmentEvent: OCKCarePlanEvent) {
        let alert: UIAlertController
        
        if assessmentEvent.activity.identifier == "sleep" {
            alert = sleepAlert(event: assessmentEvent)
        } else if assessmentEvent.activity.identifier == "weight" {
            alert = weightAlert(event: assessmentEvent)
        } else {
            return
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancelAction)

        
        present(alert, animated: true, completion: nil)
    }
    
    
    func sleepAlert(event: OCKCarePlanEvent) -> UIAlertController {
        let alert = UIAlertController(title: "Tremors", message: "How many known Tremors have you had today?", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
        }
        
        let doneAction = UIAlertAction(title: "Done", style: .default) { [unowned self] _ in
            let sleepField = alert.textFields![0]
            let result = OCKCarePlanEventResult(valueString: sleepField.text!, unitString: "times", userInfo: nil)
            self.carePlanStore.update(event, with: result, state: .completed) { (_, _, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
            }
        }
        alert.addAction(doneAction)
        
        return alert
    }
    
    func weightAlert(event: OCKCarePlanEvent) -> UIAlertController {
        let alert = UIAlertController(title: "Hand Writing", message: "How small 0-10 has your hand writing been recently?", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
        }
        let doneAction = UIAlertAction(title: "Done", style: .default) { [unowned self] _ in
            let weightField = alert.textFields![0]
            let result = OCKCarePlanEventResult(valueString: weightField.text!, unitString: "times", userInfo: nil)
            self.carePlanStore.update(event, with: result, state: .completed) { (_, _, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
            }
        }
        alert.addAction(doneAction)
        
        return alert
    }
}

extension TabBarController: OCKCarePlanStoreDelegate {
    func carePlanStore(_ store: OCKCarePlanStore, didReceiveUpdateOf event: OCKCarePlanEvent) {
        updateInsights()
    }
    
}

extension TabBarController: OCKConnectViewControllerDelegate {
    
    func connectViewController(_ connectViewController: OCKConnectViewController, didSelectShareButtonFor contact: OCKContact, presentationSourceView sourceView: UIView?) {
        var sleep = [DateComponents: Int]()
        
        let sleepDispatchGroup = DispatchGroup()
        
        sleepDispatchGroup.enter()
        fetchSleep { sleepDict in
            sleep = sleepDict
            sleepDispatchGroup.leave()
        }
        
        sleepDispatchGroup.notify(queue: .main) {
            let paragraph = OCKDocumentElementParagraph(content: "A really cool paragraph. You can include whatever you want in here.")
            let subtitle = OCKDocumentElementSubtitle(subtitle: "This Week's Tremors")
            
            let formattedDates = sleep.keys.sorted(by: {
                self.calendar.dateComponents([.second], from: $0, to: $1).second! > 0
            }).map { self.monthDayFormatter.string(from: self.calendar.date(from: $0)!) }
            let table = OCKDocumentElementTable(headers: formattedDates, rows: [sleep.values.map { "\($0) times" }])
            
            let careDocument = OCKDocument(title: "Care Data", elements: [paragraph, subtitle, table])
            careDocument.createPDFData { (pdfData, error) in
                let activityVC = UIActivityViewController(activityItems: [pdfData], applicationActivities: nil)
                activityVC.popoverPresentationController?.sourceView = sourceView
                self.present(activityVC, animated: true, completion: nil)
            }
        }
    }
    
    func connectViewController(_ connectViewController: OCKConnectViewController, titleForSharingCellFor contact: OCKContact) -> String? {
        return "Share Care Data with \(contact.name)"
    }
    
}
