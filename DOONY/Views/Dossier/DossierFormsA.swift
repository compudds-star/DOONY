import SwiftUI
import SwiftData

// MARK: - Shared UI helpers

/// FL / NY / Other state picker.
struct StatePicker: View {
    let title: String
    @Binding var selection: String
    private let options = ["FL", "NY", "Other"]
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }
}

/// Optional-date field with an enable toggle.
struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    @State private var enabled = false
    @State private var temp = Date.now
    var body: some View {
        Toggle(title, isOn: $enabled)
            .onAppear { enabled = date != nil; temp = date ?? .now }
            .onChange(of: enabled) { _, on in date = on ? temp : nil }
        if enabled {
            DatePicker(title, selection: $temp, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: temp) { _, newVal in date = newVal }
        }
    }
}

// MARK: - Advisors

struct AdvisorListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Advisor.name) private var items: [Advisor]

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { AdvisorForm(advisor: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.name.isEmpty ? "New advisor" : item.name)
                        Text("\(item.role) • \(item.state)")
                            .font(.caption).foregroundStyle(item.state == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Advisors")
        .toolbar {
            Button { let a = Advisor(); context.insert(a) } label: { Image(systemName: "plus") }
        }
    }
}

struct AdvisorForm: View {
    @Bindable var advisor: Advisor
    var body: some View {
        Form {
            Section("Advisor") {
                TextField("Name", text: $advisor.name)
                TextField("Role (physician, dentist, CPA, attorney…)", text: $advisor.role)
                TextField("Practice name", text: $advisor.practiceName)
                StatePicker(title: "Based in", selection: $advisor.state)
            }
            Section("Contact") {
                TextField("Address", text: $advisor.address, axis: .vertical)
                TextField("Phone", text: $advisor.phone).keyboardType(.phonePad)
                TextField("Email", text: $advisor.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                OptionalDateRow(title: "Patient/client since", date: $advisor.clientSince)
            }
            Section("Notes") { TextField("Notes", text: $advisor.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: advisor)
        }
        .navigationTitle("Advisor").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Vehicles

struct VehicleListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [Vehicle]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { VehicleForm(vehicle: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.makeModelYear.isEmpty ? "New vehicle" : item.makeModelYear)
                        Text("\(item.registrationState) • \(Masking.mask(item.licensePlate, visible: 3))")
                            .font(.caption).foregroundStyle(item.registrationState == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Vehicles")
        .toolbar { Button { context.insert(Vehicle()) } label: { Image(systemName: "plus") } }
    }
}

struct VehicleForm: View {
    @Bindable var vehicle: Vehicle
    var body: some View {
        Form {
            Section("Vehicle") {
                TextField("Make / model / year", text: $vehicle.makeModelYear)
                StatePicker(title: "Registered in", selection: $vehicle.registrationState)
                if vehicle.registrationState == "NY" {
                    Label("Still NY-registered — domicile red flag", systemImage: "flag.fill")
                        .foregroundStyle(.red).font(.caption)
                }
                TextField("License plate", text: $vehicle.licensePlate)
                OptionalDateRow(title: "FL registration date", date: $vehicle.registrationDate)
                TextField("VIN", text: $vehicle.vin)
                TextField("Where garaged", text: $vehicle.garagedLocation)
            }
            Section("Insurance") {
                TextField("Carrier", text: $vehicle.insuranceCarrier)
                SecureNumberField(title: "Policy #", text: $vehicle.policyNumber)
            }
            Section("Notes") { TextField("Notes", text: $vehicle.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: vehicle)
        }
        .navigationTitle("Vehicle").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Driver's license

struct DriverLicenseListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [DriverLicense]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { DriverLicenseForm(license: item) } label: {
                    VStack(alignment: .leading) {
                        Text("\(item.state) license")
                        Text(item.nyLicenseSurrenderedDate == nil ? "NY not surrendered" : "NY surrendered")
                            .font(.caption)
                            .foregroundStyle(item.nyLicenseSurrenderedDate == nil ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Driver's license")
        .toolbar { Button { context.insert(DriverLicense()) } label: { Image(systemName: "plus") } }
    }
}

struct DriverLicenseForm: View {
    @Bindable var license: DriverLicense
    var body: some View {
        Form {
            Section("License") {
                StatePicker(title: "State", selection: $license.state)
                SecureNumberField(title: "DL number", text: $license.licenseNumber)
                OptionalDateRow(title: "Issue date", date: $license.issueDate)
            }
            Section("NY surrender") {
                OptionalDateRow(title: "NY license surrendered", date: $license.nyLicenseSurrenderedDate)
                if license.nyLicenseSurrenderedDate == nil {
                    Label("Record the NY surrender date — an active NY DL is a domicile tie.",
                          systemImage: "flag.fill").foregroundStyle(.red).font(.caption)
                }
            }
            Section("Notes") { TextField("Notes", text: $license.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: license)
        }
        .navigationTitle("Driver's license").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Real property

struct RealPropertyListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [RealProperty]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { RealPropertyForm(property: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.label.isEmpty ? "New property" : item.label)
                        Text(propertySubtitle(item))
                            .font(.caption)
                            .foregroundStyle(item.isNYAbode && item.stillOwned ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Real property")
        .toolbar { Button { context.insert(RealProperty()) } label: { Image(systemName: "plus") } }
    }

    private func propertySubtitle(_ p: RealProperty) -> String {
        if p.state == "NY" { return p.stillOwned ? "NY abode — still owned" : "NY — sold" }
        return "FL" + (p.homesteadFilingDate != nil ? " • homestead filed" : "")
    }
}

struct RealPropertyForm: View {
    @Bindable var property: RealProperty
    var body: some View {
        Form {
            Section("Property") {
                TextField("Label (e.g. Delray Beach condo)", text: $property.label)
                StatePicker(title: "State", selection: $property.state)
                TextField("Address", text: $property.address, axis: .vertical)
            }
            if property.state == "FL" {
                Section("Florida domicile filings") {
                    OptionalDateRow(title: "Homestead exemption filed", date: $property.homesteadFilingDate)
                    OptionalDateRow(title: "Declaration of Domicile recorded", date: $property.declarationOfDomicileDate)
                    TextField("Recording book/page", text: $property.declarationBookPage)
                }
            }
            Section("NY abode status") {
                Toggle("Counts as a NY permanent place of abode", isOn: $property.isNYAbode)
                Toggle("Still owned", isOn: $property.stillOwned)
                OptionalDateRow(title: "Sold date", date: $property.soldDate)
                if property.isNYAbode && property.stillOwned {
                    Label("Retained NY abode — primary driver of the 183-day statutory-resident test.",
                          systemImage: "flag.fill").foregroundStyle(.red).font(.caption)
                }
            }
            Section("Notes") { TextField("Notes", text: $property.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: property)
        }
        .navigationTitle("Property").navigationBarTitleDisplayMode(.inline)
    }
}

/// A masked entry field for sensitive numbers (DL, policy, account). The raw
/// value is bound directly (encrypted at rest); the field reveals on demand only.
struct SecureNumberField: View {
    let title: String
    @Binding var text: String
    @State private var revealed = false
    var body: some View {
        HStack {
            if revealed {
                TextField(title, text: $text)
            } else {
                Text(text.isEmpty ? title : Masking.mask(text))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                Spacer()
            }
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }.buttonStyle(.borderless)
        }
    }
}
