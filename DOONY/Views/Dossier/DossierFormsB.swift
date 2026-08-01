import SwiftUI
import SwiftData

// MARK: - Voter registration

struct VoterListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [VoterRegistration]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { VoterForm(voter: item) } label: {
                    VStack(alignment: .leading) {
                        Text("\(item.county.isEmpty ? "County" : item.county), \(item.state)")
                        Text("\(item.electionsVoted.count) elections logged")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Voter registration")
        .toolbar { Button { context.insert(VoterRegistration()) } label: { Image(systemName: "plus") } }
    }
}

struct VoterForm: View {
    @Bindable var voter: VoterRegistration
    @State private var newElection = ""
    var body: some View {
        Form {
            Section("Registration") {
                StatePicker(title: "State", selection: $voter.state)
                TextField("County", text: $voter.county)
                OptionalDateRow(title: "Registration date", date: $voter.registrationDate)
            }
            Section("Elections voted (FL)") {
                ForEach(voter.electionsVoted, id: \.self) { Text($0) }
                    .onDelete { voter.electionsVoted.remove(atOffsets: $0) }
                HStack {
                    TextField("e.g. 2024-11-05 General", text: $newElection)
                    Button("Add") {
                        guard !newElection.isEmpty else { return }
                        voter.electionsVoted.append(newElection); newElection = ""
                    }
                }
            }
            Section("Notes") { TextField("Notes", text: $voter.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: voter)
        }
        .navigationTitle("Voter").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Financial ties

struct FinancialListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [FinancialTie]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { FinancialForm(tie: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.institution.isEmpty ? "New institution" : item.institution)
                        Text("\(item.kind) • \(item.state)")
                            .font(.caption).foregroundStyle(item.state == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Financial ties")
        .toolbar { Button { context.insert(FinancialTie()) } label: { Image(systemName: "plus") } }
    }
}

struct FinancialForm: View {
    @Bindable var tie: FinancialTie
    private let kinds = ["bank", "brokerage", "safe deposit box", "credit card"]
    var body: some View {
        Form {
            Section("Institution") {
                TextField("Name", text: $tie.institution)
                Picker("Kind", selection: $tie.kind) { ForEach(kinds, id: \.self) { Text($0) } }
                StatePicker(title: "State / billing", selection: $tie.state)
                SecureNumberField(title: "Account reference", text: $tie.accountReference)
                OptionalDateRow(title: "Moved to FL", date: $tie.movedToFLDate)
            }
            Section("Notes") { TextField("Notes", text: $tie.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: tie)
        }
        .navigationTitle("Financial tie").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Near-and-dear items & people

struct NearDearListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [NearAndDearItem]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { NearDearForm(item: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.descriptionText.isEmpty ? "New item" : item.descriptionText)
                        Text("\(item.category) • \(item.state)")
                            .font(.caption).foregroundStyle(item.state == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Near & dear")
        .toolbar { Button { context.insert(NearAndDearItem()) } label: { Image(systemName: "plus") } }
    }
}

struct NearDearForm: View {
    @Bindable var item: NearAndDearItem
    private let categories = ["item", "pet", "family member", "collection", "holiday location"]
    var body: some View {
        Form {
            Section {
                TextField("Description (heirloom, pet, spouse…)", text: $item.descriptionText)
                Picker("Category", selection: $item.category) { ForEach(categories, id: \.self) { Text($0) } }
                StatePicker(title: "State", selection: $item.state)
                TextField("Location", text: $item.location)
            }
            Section("Notes") { TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: item)
        }
        .navigationTitle("Near & dear").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Memberships

struct MembershipListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [Membership]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { MembershipForm(membership: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.organization.isEmpty ? "New membership" : item.organization)
                        Text("\(item.kind) • \(item.state)")
                            .font(.caption).foregroundStyle(item.state == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Memberships")
        .toolbar { Button { context.insert(Membership()) } label: { Image(systemName: "plus") } }
    }
}

struct MembershipForm: View {
    @Bindable var membership: Membership
    private let kinds = ["club", "religious", "social", "professional"]
    var body: some View {
        Form {
            Section {
                TextField("Organization", text: $membership.organization)
                Picker("Kind", selection: $membership.kind) { ForEach(kinds, id: \.self) { Text($0) } }
                StatePicker(title: "State", selection: $membership.state)
                OptionalDateRow(title: "Member since", date: $membership.since)
            }
            Section("Notes") { TextField("Notes", text: $membership.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: membership)
        }
        .navigationTitle("Membership").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Employment / business

struct EmploymentListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [EmploymentBusiness]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { EmploymentForm(item: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.name.isEmpty ? "New affiliation" : item.name)
                        Text("\(item.role) • \(item.state)\(item.isProfessionalLicense ? " • license" : "")")
                            .font(.caption).foregroundStyle(item.state == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Employment / business")
        .toolbar { Button { context.insert(EmploymentBusiness()) } label: { Image(systemName: "plus") } }
    }
}

struct EmploymentForm: View {
    @Bindable var item: EmploymentBusiness
    var body: some View {
        Form {
            Section {
                TextField("Name (business / employer)", text: $item.name)
                TextField("Role", text: $item.role)
                StatePicker(title: "State", selection: $item.state)
                Toggle("Professional license (e.g. NY dental license)", isOn: $item.isProfessionalLicense)
                if item.state == "NY" {
                    Label("NY-based \(item.isProfessionalLicense ? "license" : "business") — domicile risk factor.",
                          systemImage: "flag.fill").foregroundStyle(.red).font(.caption)
                }
            }
            Section("Notes") { TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: item)
        }
        .navigationTitle("Affiliation").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Mailing / document addresses

struct MailingListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [MailingAddressRecord]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { MailingForm(record: item) } label: {
                    VStack(alignment: .leading) {
                        Text(item.documentType)
                        Text(item.addressState)
                            .font(.caption).foregroundStyle(item.addressState == "NY" ? .red : .secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Document addresses")
        .toolbar { Button { context.insert(MailingAddressRecord()) } label: { Image(systemName: "plus") } }
    }
}

struct MailingForm: View {
    @Bindable var record: MailingAddressRecord
    private let types = ["passport", "federal tax return", "insurance", "estate documents", "primary credit card"]
    var body: some View {
        Form {
            Section {
                Picker("Document", selection: $record.documentType) { ForEach(types, id: \.self) { Text($0) } }
                StatePicker(title: "Address on file", selection: $record.addressState)
                TextField("Address", text: $record.address, axis: .vertical)
            }
            Section("Key dates") {
                OptionalDateRow(title: "IRS Form 8822 filed", date: $record.irsForm8822Date)
                OptionalDateRow(title: "FL will/trust executed", date: $record.estateDocExecutionDate)
            }
            Section("Notes") { TextField("Notes", text: $record.notes, axis: .vertical).lineLimit(2...6) }
            AttachmentsSection(owner: record)
        }
        .navigationTitle("Document").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Nightly residence log

struct ResidenceNightListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ResidenceNight.date, order: .reverse) private var items: [ResidenceNight]
    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink { ResidenceNightForm(night: item) } label: {
                    HStack {
                        Text(item.date, style: .date)
                        Spacer()
                        Text("\(item.location) (\(item.state))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { $0.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Nightly log")
        .toolbar { Button { context.insert(ResidenceNight()) } label: { Image(systemName: "plus") } }
    }
}

struct ResidenceNightForm: View {
    @Bindable var night: ResidenceNight
    var body: some View {
        Form {
            DatePicker("Date", selection: $night.date, displayedComponents: .date)
            TextField("Location (FL condo, NY home…)", text: $night.location)
            StatePicker(title: "State", selection: $night.state)
            TextField("Notes", text: $night.notes, axis: .vertical).lineLimit(2...6)
        }
        .navigationTitle("Night").navigationBarTitleDisplayMode(.inline)
    }
}
