import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllObjectOptions from '@salesforce/apex/ScArchAdminController.getAllObjectOptions';
import getRelatedObjects from '@salesforce/apex/ScArchAdminController.getRelatedObjects';
import getRelatedLookupObjects from '@salesforce/apex/ScArchAdminController.getRelatedLookupObjects';
import getAdminConfiguration from '@salesforce/apex/ScArchAdminController.getAdminConfiguration';
import getCompanyInformation from '@salesforce/apex/ScArchAdminController.getCompanyInformation';
import registerOrg from '@salesforce/apex/ScArchAdminController.registerOrg';
import registerInstance from '@salesforce/apex/ScArchAdminController.registerInstance';
import renewSubscription from '@salesforce/apex/ScArchAdminController.renewSubscription';
import saveObjectDetailConfiguration from '@salesforce/apex/ScArchAdminController.saveObjectDetailConfiguration';
import saveQuickSchedule from '@salesforce/apex/ScArchAdminController.saveQuickSchedule';
import updateArchiveConfiguration from '@salesforce/apex/ScArchAdminController.updateArchiveConfiguration';
import deleteArchiveConfiguration from '@salesforce/apex/ScArchAdminController.deleteArchiveConfiguration';
import validateNamedCredential from '@salesforce/apex/ScArchAdminController.validateNamedCredential';

export default class ScArchAdminCenter extends LightningElement {
    isLoading = false;

    // Registration Form
    orgId = '';
    orgName = '';
    isProd = '';
    instanceName = '';
    country = '';
    state = '';
    city = '';
    postalCode = '';
    phone = '';
    fax = '';
    website = '';
    language = '';
    timeZone = '';
    createdDate = '';
    firstName = '';
    lastName = '';
    companyName = '';
    email = '';
    productKey = '';
    dataHostedToggle = false;
    renewalKey = '';
    registrationStatus = '';
    subscriptionStatus = '';
    subscriptionLicenseStatus = '';
    subscriptionExpiry = '';

    get isRenewalDisabled() {
        return !this.renewalKey;
    }

    isValidSalesforceId(id) {
        return typeof id === 'string' && /^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?$/.test(id);
    }

    // Client Details
    clientName = '';
    clientId = '';
    clientSecret = '';
    licenseKey = '';

    // Webserver Setup
    namedCredential = '';

    // Database Setup
    dbHost = '';
    dbPort = '5432';
    dbName = '';
    dbUser = '';
    dbPass = '';

    // Salesforce Setup
    sfUsername = '';
    sfToken = '';
    sfDomain = 'login';
    namedCredentialError = '';
    isNamedCredentialValid = true;

    // Object Details
    objectEntries = [
        {
            id: 1,
            objectName: '',
            frequency: '',
            fieldSetName: '',
            isParent: false,
            archiveChildren: false,
            hasDocuments: false,
            firstArchiveDate: '',
            lastArchiveDate: '',
            selectedRelatedObjects: [],
            relatedObjects: [],
            relatedLookupObjects: [],
            selectedRelatedObjectsMaster: [],
            selectedRelatedObjectsLookup: [],
            loadingRelatedObjects: false,
            hasNoRelatedObjects: false,
            isExisting: false,
            objectOptions: []
        }
    ];
    scheduledJobs = [];
    existingScheduledJobs = [];
    isAdminConfigLoaded = false;
    nextEntryId = 2;
    activeTab = 'quickSchedule';
    showObjectDetailsTab = false;
    showEditModal = false;
    editModalEntry = null;
    editModalRenderToken = 0;
    scheduledJobActions = [
        { label: 'Edit', name: 'edit' },
        { label: 'Delete', name: 'delete' }
    ];

    get scheduledJobColumns() {
        return [
            { label: 'Object', fieldName: 'objectName', type: 'text' },
            { label: 'Frequency', fieldName: 'frequency', type: 'text' },
            { label: 'Status', fieldName: 'status', type: 'text' },
            { label: 'Next Run', fieldName: 'nextRun', type: 'text' },
            { label: 'Archive Children', fieldName: 'archiveChildren', type: 'boolean' },
            {
                label: 'Actions',
                type: 'action',
                fixedWidth: 90,
                typeAttributes: {
                    rowActions: this.scheduledJobActions
                }
            }
        ];
    }

    get isObjectDetailsTab() {
        return String(this.activeTab || 'objectDetails') === 'objectDetails';
    }

    get isQuickScheduleTab() {
        return String(this.activeTab || 'objectDetails') === 'quickSchedule';
    }

    // Options
    domainOptions = [
        { label: 'Production', value: 'login' },
        { label: 'Sandbox', value: 'test' },
        { label: 'Custom Domain', value: 'custom' }
    ];
    objectOptions = [];
    relatedObjectsMap = {};
    relatedObjectsLookupMap = {};

    frequencyOptions = [
        { label: 'Daily', value: 'Daily' },
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Monthly', value: 'Monthly' },
        { label: '3 Months', value: '3 Months' }
    ];

    @wire(getAllObjectOptions)
    wiredObjectOptions({ error, data }) {
        if (data) {
            this.objectOptions = data;
            this.refreshObjectEntryOptions();
        } else if (error) {
            console.error('Failed to load object picklist values', error);
        }
    }

    @wire(getCompanyInformation)
    wiredCompanyInformation({ error, data }) {
        if (data) {
            this.orgId = data.orgId || '';
            this.orgName = data.orgName || '';
            this.companyName = data.orgName || '';
            this.isProd = data.isProd ? 'Yes' : 'No';
            this.instanceName = data.instanceName || '';
            this.country = data.country || '';
            this.state = data.state || '';
            this.city = data.city || '';
            this.postalCode = data.postalCode || '';
            this.phone = data.phone || '';
            this.fax = data.fax || '';
            this.website = data.website || '';
            this.language = data.language || '';
            this.timeZone = data.timeZone || '';
            this.createdDate = data.createdDate || '';
            this.firstName = data.firstName || '';
            this.lastName = data.lastName || '';
            this.email = data.email || '';
        } else if (error) {
            console.error('Failed to load company information', error);
        }
    }

    connectedCallback() {
        this.loadAdminConfiguration();
    }

    async loadAdminConfiguration() {
        this.isAdminConfigLoaded = false;
        try {
            const data = await getAdminConfiguration();
            if (data) {
                this.hydrateAdminConfiguration(data);
            } else {
                this.isAdminConfigLoaded = true;
            }
        } catch (error) {
            this.isAdminConfigLoaded = true;
            console.error('Failed to load admin configuration', error);
        }
    }

    hydrateAdminConfiguration(data) {
        this.isAdminConfigLoaded = true;
        this.clientName = data.clientName || '';
        this.clientId = data.clientId || '';
        this.clientSecret = data.clientSecret || '';
        this.licenseKey = data.licenseKey || '';
        this.productKey = data.productKey || '';
        this.registrationStatus = data.registrationStatus || '';
        this.subscriptionExpiry = data.subscriptionExpiry || '';
        this.namedCredential = data.namedCredential || '';
        this.dbHost = data.dbHost || '';
        this.dbPort = data.dbPort || '5432';
        this.dbName = data.dbName || '';
        this.dbUser = data.dbUser || '';
        this.dbPass = data.dbPass || '';
        this.sfUsername = data.sfUsername || '';
        this.sfToken = data.sfToken || '';
        this.sfDomain = data.sfDomain || 'login';

        this.existingScheduledJobs = Array.isArray(data.objectEntries)
            ? data.objectEntries.map((entry) => ({
                id: entry.id || entry.recordId || entry.rowKey || Math.random().toString(36).slice(2),
                objectName: entry.objectName || '',
                frequency: entry.frequency || '',
                fieldSetName: entry.fieldSetName || '',
                isParent: entry.isParent === true,
                archiveChildren: entry.archiveChildren === true,
                hasDocuments: entry.hasDocuments === true,
                firstArchiveDate: entry.firstArchiveDate || '',
                lastArchiveDate: entry.lastArchiveDate || '',
                selectedRelatedObjects: Array.isArray(entry.selectedRelatedObjects) ? entry.selectedRelatedObjects : [],
                masterRelatedObjects: Array.isArray(entry.masterRelatedObjects) ? entry.masterRelatedObjects : [],
                lookupRelatedObjects: Array.isArray(entry.lookupRelatedObjects) ? entry.lookupRelatedObjects : [],
                status: entry.status || entry.Status__c || 'Active',
                nextRun: entry.firstArchiveDate || 'Pending',
                configId: entry.recordId || entry.id || null,
                rowKey: entry.rowKey || null,
                sourceKey: entry.recordId || entry.id || entry.rowKey || null
            }))
            : [];

        this.syncObjectSelectionAvailability();

        // Diagnostic: log how many persisted scheduled jobs were returned by the server
        try {
            // eslint-disable-next-line no-console
            console.log('[scArchAdminCenter] Loaded existingScheduledJobs count', { count: this.existingScheduledJobs.length, sample: this.existingScheduledJobs.slice(0, 5) });
        } catch (e) {
            // ignore logging errors
        }

        this.objectEntries = [{
            id: 1,
            objectName: '',
            frequency: '',
            fieldSetName: '',
            isParent: false,
            archiveChildren: false,
            hasDocuments: false,
            firstArchiveDate: '',
            lastArchiveDate: '',
            selectedRelatedObjects: [],
            selectedRelatedObjectsMaster: [],
            selectedRelatedObjectsLookup: [],
            relatedObjects: [],
            relatedLookupObjects: [],
            loadingRelatedObjects: false,
            hasNoRelatedObjects: false,
            isExisting: false,
            recordId: null,
            rowKey: null,
            objectOptions: this.getAvailableObjectOptionsForEntry(1)
        }];
        this.nextEntryId = 2;
        this.buildScheduledJobsSummary();

        if (this.existingScheduledJobs.length > 0 && this.activeTab !== 'scheduledJobs') {
            this.activeTab = 'scheduledJobs';
        }
    }

    getAvailableObjectOptionsForEntry(entryId) {
        const usedObjectNames = new Set();
        this.existingScheduledJobs.forEach((job) => {
            if (job && job.objectName) {
                usedObjectNames.add(job.objectName);
            }
        });

        this.objectEntries.forEach((entry) => {
            if (entry && entry.id !== entryId && entry.objectName) {
                usedObjectNames.add(entry.objectName);
            }
        });

        const selectedValue = this.objectEntries.find((entry) => entry.id === entryId)?.objectName;
        const safeOptions = Array.isArray(this.objectOptions) ? this.objectOptions : [];
        return safeOptions.filter((option) => {
            const value = option && option.value ? String(option.value) : '';
            return !usedObjectNames.has(value) || (selectedValue && value === selectedValue);
        });
    }

    refreshObjectEntryOptions() {
        this.objectEntries = this.objectEntries.map((entry) => ({
            ...entry,
            objectOptions: this.getAvailableObjectOptionsForEntry(entry.id)
        }));
    }

    syncObjectSelectionAvailability() {
        this.refreshObjectEntryOptions();
    }

    async refreshAdminConfiguration() {
        await this.loadAdminConfiguration();
    }

    handleObjectEntryChange(event) {
        const entryId = Number(event.target.dataset.id);
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.type === 'checkbox'
                ? event.target.checked
                : event.target.value;

        this.objectEntries = this.objectEntries.map((entry) => {
            if (entry.id !== entryId) {
                return entry;
            }
            
            const updatedEntry = {
                ...entry,
                [field]: value,
                objectOptions: this.getAvailableObjectOptionsForEntry(entry.id)
            };

            if (field === 'objectName') {
                updatedEntry.fieldSetName = '';
            }

            // If archiveChildren is being unchecked, clear selected related objects
            if (field === 'archiveChildren' && !value) {
                updatedEntry.selectedRelatedObjects = [];
                updatedEntry.relatedObjects = [];
                updatedEntry.loadingRelatedObjects = false;
                updatedEntry.hasNoRelatedObjects = false;
            }

            return updatedEntry;
        });

        this.buildScheduledJobsSummary();

        // Load related objects asynchronously if needed
        const entry = this.objectEntries.find(e => e.id === entryId);
        if ((field === 'archiveChildren' && value && entry?.objectName) || 
            (field === 'objectName' && entry?.archiveChildren)) {
            this.loadRelatedObjectsForEntry(entryId, entry.objectName);
        }
    }

    handleQuickScheduleRelatedMasterChange(event) {
        const entryId = Number(event.target.dataset.id || event.target.closest('[data-id]')?.dataset?.id);
        const selected = event.detail && event.detail.value ? event.detail.value : [];
        this.objectEntries = this.objectEntries.map(entry => {
            if (entry.id === entryId) {
                return { ...entry, selectedRelatedObjectsMaster: selected };
            }
            return entry;
        });
    }

    handleQuickScheduleRelatedLookupChange(event) {
        const entryId = Number(event.target.dataset.id || event.target.closest('[data-id]')?.dataset?.id);
        const selected = event.detail && event.detail.value ? event.detail.value : [];
        this.objectEntries = this.objectEntries.map(entry => {
            if (entry.id === entryId) {
                return { ...entry, selectedRelatedObjectsLookup: selected };
            }
            return entry;
        });
    }

    buildScheduledJobsSummary() {
        const toUniqueList = (values) => {
            const normalized = [];
            const seen = new Set();
            const entries = Array.isArray(values) ? values : [];

            entries.forEach((value) => {
                const name = typeof value === 'string' ? value.trim() : (value != null ? String(value).trim() : '');
                if (!name || seen.has(name)) {
                    return;
                }
                seen.add(name);
                normalized.push(name);
            });

            return normalized;
        };

        const buildRelatedRows = (job) => {
            const relationshipNames = [
                ...(Array.isArray(job.selectedRelatedObjects) ? job.selectedRelatedObjects : []),
                ...(Array.isArray(job.masterRelatedObjects) ? job.masterRelatedObjects : []),
                ...(Array.isArray(job.lookupRelatedObjects) ? job.lookupRelatedObjects : [])
            ];

            const uniqueRelations = toUniqueList(relationshipNames);
            if (!uniqueRelations.length) {
                return [];
            }

            return uniqueRelations.map((relatedObjectName, relationIndex) => ({
                ...job,
                id: `${job.id || job.configId || job.rowKey || 'job'}_related_${relationIndex}_${relatedObjectName}`,
                objectName: relatedObjectName,
                parentObjectName: job.objectName || '',
                relationshipType: 'related',
                isRelatedObjectRow: true,
                status: job.status || 'Configured',
                nextRun: job.nextRun || job.firstArchiveDate || 'Pending'
            }));
        };

        const persistedJobs = this.existingScheduledJobs.map((job) => ({
            ...job,
            id: job.id || job.configId || job.rowKey,
            status: job.status || 'Configured',
            nextRun: job.nextRun || job.firstArchiveDate || 'Pending',
            configId: job.configId || job.id,
            rowKey: job.rowKey || null,
            sourceKey: job.sourceKey || job.configId || job.id || job.rowKey || null,
            selectedRelatedObjects: Array.isArray(job.selectedRelatedObjects) ? job.selectedRelatedObjects : [],
            masterRelatedObjects: Array.isArray(job.masterRelatedObjects) ? job.masterRelatedObjects : [],
            lookupRelatedObjects: Array.isArray(job.lookupRelatedObjects) ? job.lookupRelatedObjects : []
        }));

        const draftJobs = this.objectEntries
            .filter((entry) => entry.objectName && entry.frequency)
            .map((entry) => ({
                // Use a prefixed draft id to avoid colliding with persisted numeric configIds
                id: `draft_${entry.id}`,
                objectName: entry.objectName,
                frequency: entry.frequency,
                status: entry.isExisting ? 'Configured' : 'New',
                nextRun: entry.firstArchiveDate || 'Pending',
                archiveChildren: entry.archiveChildren === true,
                // Keep configId only when a persisted recordId exists
                configId: entry.recordId || null,
                rowKey: entry.rowKey || null,
                sourceKey: entry.recordId || entry.rowKey || null,
                fieldSetName: entry.fieldSetName || '',
                isParent: entry.isParent === true,
                hasDocuments: entry.hasDocuments === true,
                firstArchiveDate: entry.firstArchiveDate || '',
                lastArchiveDate: entry.lastArchiveDate || '',
                selectedRelatedObjects: Array.isArray(entry.selectedRelatedObjects) ? entry.selectedRelatedObjects : [],
                masterRelatedObjects: Array.isArray(entry.selectedRelatedObjectsMaster) ? entry.selectedRelatedObjectsMaster : [],
                lookupRelatedObjects: Array.isArray(entry.selectedRelatedObjectsLookup) ? entry.selectedRelatedObjectsLookup : []
            }));

        const relatedRows = [];
        persistedJobs.forEach((job) => {
            relatedRows.push(...buildRelatedRows(job));
        });
        draftJobs.forEach((job) => {
            relatedRows.push(...buildRelatedRows(job));
        });

        // Ensure unique string IDs for each row to avoid datatable mapping issues
        const combined = [...persistedJobs, ...relatedRows, ...draftJobs];
        const timestamp = Date.now();

        // Build ids and ensure uniqueness even when backend returns duplicate ids
        const seen = new Set();
        this.scheduledJobs = combined.map((job, idx) => {
            const baseId = job.configId ?? job.recordId ?? job.sourceKey ?? job.rowKey ?? job.id ?? null;
            let normalized = baseId != null ? String(baseId) : `__local_${idx}_${timestamp}`;

            if (seen.has(normalized)) {
                // Append an index suffix to guarantee uniqueness
                normalized = `${normalized}_${idx}`;
            }
            seen.add(normalized);

            return {
                ...job,
                id: normalized,
                // keep originalBaseId for matching when events may provide unsuffixed ids
                _baseId: baseId != null ? String(baseId) : null
            };
        });

        // Diagnostic: warn if there are duplicate ids which can break row-action mapping
        try {
            const ids = this.scheduledJobs.map(j => j.id);
            const duplicates = ids.filter((id, idx) => id != null && ids.indexOf(id) !== idx);
            if (duplicates.length) {
                // eslint-disable-next-line no-console
                console.warn('[scArchAdminCenter] Duplicate scheduledJobs id(s) detected:', Array.from(new Set(duplicates)));
            }
        } catch (e) {
            // ignore diagnostics errors
        }
    }

    handleRelatedObjectChange(event) {
        const entryId = Number(event.target.dataset.id);
        const selectedValues = event.detail.value; // dual-listbox returns selected values as array

        this.objectEntries = this.objectEntries.map((entry) => {
            if (entry.id !== entryId) {
                return entry;
            }

            return {
                ...entry,
                selectedRelatedObjects: selectedValues
            };
        });
    }

    handleTabChange(event) {
        const selectedTabRaw = event && event.detail && event.detail.value !== undefined
            ? event.detail.value
            : (event && event.currentTarget && event.currentTarget.value !== undefined ? event.currentTarget.value : this.activeTab);

        const selectedTab = String(selectedTabRaw || 'objectDetails');
        this.activeTab = selectedTab;
        console.log('[scArchAdminCenter] Tab changed', {
            selectedTab,
            selectedTabRaw,
            detailValue: event && event.detail ? event.detail.value : null,
            currentTargetValue: event && event.currentTarget ? event.currentTarget.value : null,
            typeOfSelectedTab: typeof selectedTabRaw
        });
    }

    handleTabSelection(event) {
        const selectedTab = event && event.currentTarget && event.currentTarget.value
            ? String(event.currentTarget.value)
            : 'objectDetails';

        this.activeTab = selectedTab;
        console.log('[scArchAdminCenter] Tab selected explicitly', {
            selectedTab,
            currentTargetValue: event && event.currentTarget ? event.currentTarget.value : null
        });
    }

    async handleScheduledJobRowAction(event) {
        const actionName = event.detail && event.detail.action ? event.detail.action.name : null;
        const row = event.detail && event.detail.row ? event.detail.row : null;

        // Convert LWC reactive Proxy to a plain object for reliable inspection
        let rowPlain = null;
        try {
            rowPlain = row ? JSON.parse(JSON.stringify(row)) : null;
        } catch (e) {
            rowPlain = row || null;
        }

        // Diagnostic logging: extract key properties reliably and log them as JSON
        const keyProps = {
            id: (row && row.id) || (rowPlain && rowPlain.id) || null,
            objectName: (row && row.objectName) || (rowPlain && rowPlain.objectName) || null,
            frequency: (row && row.frequency) || (rowPlain && rowPlain.frequency) || null,
            nextRun: (row && row.nextRun) || (rowPlain && rowPlain.nextRun) || null,
            configId: (row && row.configId) || (rowPlain && rowPlain.configId) || null,
            sourceKey: (row && row.sourceKey) || (rowPlain && rowPlain.sourceKey) || null
        };

        const safeStringify = (obj) => {
            try {
                return JSON.stringify(obj);
            } catch (e) {
                try {
                    // fallback: stringify only enumerable plain props
                    const plain = {};
                    Object.keys(obj || {}).forEach(k => { plain[k] = obj[k]; });
                    return JSON.stringify(plain);
                } catch (e2) {
                    return String(obj);
                }
            }
        };

        try {
            // eslint-disable-next-line no-console
            console.log('[scArchAdminCenter] Row action invoked', safeStringify({ actionName, keyProps }));
        } catch (e) {
            // ignore logging errors
        }

        // Try to find the original job object from the cached scheduledJobs array using the normalized id
        const normalizedId = keyProps.id != null ? String(keyProps.id) : null;
        let resolvedRow = (normalizedId && this.scheduledJobs && Array.isArray(this.scheduledJobs))
            ? this.scheduledJobs.find(j => String(j.id) === normalizedId) || null
            : null;

        // If exact id match failed, try to match by base id (handles suffixes appended to avoid collisions)
        if (!resolvedRow && normalizedId && Array.isArray(this.scheduledJobs)) {
            resolvedRow = this.scheduledJobs.find(j => j._baseId && String(j._baseId) === normalizedId) ||
                this.scheduledJobs.find(j => String(j.id).startsWith(`${normalizedId}_`)) || null;
        }

        // Fallback: try to match by objectName+frequency+nextRun if id lookup failed
        if (!resolvedRow && keyProps.objectName) {
            resolvedRow = (this.scheduledJobs || []).find(j =>
                String(j.objectName) === String(keyProps.objectName) &&
                (keyProps.frequency ? String(j.frequency) === String(keyProps.frequency) : true) &&
                (keyProps.nextRun ? String(j.nextRun) === String(keyProps.nextRun) : true)
            ) || null;
        }

        try {
            if (resolvedRow) {
                // eslint-disable-next-line no-console
                console.log('[scArchAdminCenter] Resolved scheduledJobs entry', safeStringify({ resolvedId: resolvedRow.id, resolvedKeyProps: { id: resolvedRow.id, objectName: resolvedRow.objectName, frequency: resolvedRow.frequency, nextRun: resolvedRow.nextRun } }));
            } else {
                // eslint-disable-next-line no-console
                console.log('[scArchAdminCenter] Could not resolve scheduledJobs entry by id; existing scheduledJobs ids:', safeStringify((this.scheduledJobs || []).map(j => j.id)));
            }
        } catch (e) {
            // ignore logging errors
        }

        // Use resolvedRow below in place of `row` for source lookups

        if (actionName === 'delete') {
            this.handleDeleteScheduledJob(row);
            return;
        }

        if (actionName !== 'edit') {
            return;
        }

        this.closeEditModal();

        const rowSourceKey = resolvedRow?.sourceKey ?? resolvedRow?.configId ?? resolvedRow?.recordId ?? resolvedRow?.rowKey ?? resolvedRow?.id;

        // Prefer the resolvedRow (which was matched against the datatable rows) to avoid
        // collisions when multiple persisted entries share the same base id.
        const sourceEntry = resolvedRow || this.existingScheduledJobs.find((job) => {
            const jobSourceKey = job.sourceKey ?? job.configId ?? job.recordId ?? job.rowKey ?? job.id;
            return jobSourceKey != null && rowSourceKey != null && String(jobSourceKey) === String(rowSourceKey);
        }) || this.objectEntries.find((entry) => {
            const entrySourceKey = entry.recordId ?? entry.rowKey ?? entry.id;
            return entrySourceKey != null && rowSourceKey != null && String(entrySourceKey) === String(rowSourceKey);
        }) || row;

        const objectName = sourceEntry.objectName || row.objectName || '';
        const archiveChildren = sourceEntry.archiveChildren === true || row.archiveChildren === true;
        const selectedRelatedObjects = Array.isArray(sourceEntry.selectedRelatedObjects)
            ? [...sourceEntry.selectedRelatedObjects]
            : Array.isArray(row.selectedRelatedObjects)
                ? [...row.selectedRelatedObjects]
                : [];

        let relatedObjects = this.relatedObjectsMap[objectName] || [];
        if (objectName && archiveChildren) {
            try {
                const fetchedRelatedObjects = await getRelatedObjects({ objectName });
                this.relatedObjectsMap = {
                    ...this.relatedObjectsMap,
                    [objectName]: fetchedRelatedObjects
                };
                relatedObjects = fetchedRelatedObjects;
            } catch (error) {
                console.error('Failed to load related objects for edit modal', error);
                relatedObjects = [];
            }
        }

        // Determine the actual Salesforce record id to use for saves (must be 15/18 char SF id)
        let candidateRecordId = sourceEntry.configId ?? sourceEntry.recordId ?? resolvedRow?._baseId ?? resolvedRow?.configId ?? row.configId ?? row.recordId ?? row.id;
        if (!this.isValidSalesforceId(candidateRecordId)) {
            candidateRecordId = null;
        }

        const nextModalEntry = {
            id: sourceEntry.id ?? row.id,
            objectName,
            frequency: sourceEntry.frequency ?? row.frequency ?? '',
            fieldSetName: sourceEntry.fieldSetName ?? row.fieldSetName ?? '',
            isParent: sourceEntry.isParent === true || row.isParent === true,
            archiveChildren,
            hasDocuments: sourceEntry.hasDocuments === true || row.hasDocuments === true,
            firstArchiveDate: sourceEntry.firstArchiveDate ?? row.firstArchiveDate ?? '',
            lastArchiveDate: sourceEntry.lastArchiveDate ?? row.lastArchiveDate ?? '',
            selectedRelatedObjects,
            relatedObjects,
            loadingRelatedObjects: false,
            hasNoRelatedObjects: relatedObjects.length === 0,
            isExisting: !!candidateRecordId,
            recordId: candidateRecordId,
            rowKey: sourceEntry.rowKey ?? row.rowKey ?? null
        };

        this.editModalRenderToken += 1;
        this.editModalEntry = { ...nextModalEntry };
        this.showEditModal = true;
    }

    closeEditModal() {
        this.showEditModal = false;
        this.editModalEntry = null;
        this.editModalRenderToken += 1;
    }

    handleEditModalChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.type === 'checkbox'
                ? event.target.checked
                : event.target.value;

        this.editModalEntry = {
            ...this.editModalEntry,
            [field]: value
        };

        if (field === 'archiveChildren' && !value) {
            this.editModalEntry.selectedRelatedObjects = [];
        }
    }

    handleEditModalRelatedObjectChange(event) {
        this.editModalEntry = {
            ...this.editModalEntry,
            selectedRelatedObjects: event.detail.value || []
        };
    }

    handleEditModalFieldSelectionChange(event) {
        this.editModalEntry = {
            ...this.editModalEntry,
            fieldSetName: event.detail && event.detail.value ? event.detail.value : ''
        };
    }

    async handleSaveEditedJob() {
        if (!this.editModalEntry) {
            return;
        }

        const payload = {
            id: this.editModalEntry.recordId || this.editModalEntry.id,
            objectName: this.editModalEntry.objectName || '',
            frequency: this.editModalEntry.frequency || '',
            fieldSetName: this.editModalEntry.fieldSetName || '',
            isParent: this.editModalEntry.isParent === true,
            archiveChildren: this.editModalEntry.archiveChildren === true,
            hasDocuments: this.editModalEntry.hasDocuments === true,
            firstArchiveDate: this.editModalEntry.firstArchiveDate || '',
            lastArchiveDate: this.editModalEntry.lastArchiveDate || '',
            selectedRelatedObjects: Array.isArray(this.editModalEntry.selectedRelatedObjects)
                ? this.editModalEntry.selectedRelatedObjects
                : []
        };

        try {
            if (this.editModalEntry.recordId) {
                // Existing persisted config: call update
                await updateArchiveConfiguration({
                    configId: this.editModalEntry.recordId,
                    configJson: JSON.stringify(payload)
                });
            } else {
                // New/draft entry: call saveObjectDetailConfiguration to create records
                const createPayload = {
                    objectEntries: [
                        {
                            id: this.editModalEntry.id,
                            objectName: payload.objectName,
                            frequency: payload.frequency,
                            fieldSetName: payload.fieldSetName,
                            isParent: payload.isParent,
                            archiveChildren: payload.archiveChildren,
                            hasDocuments: payload.hasDocuments,
                            firstArchiveDate: payload.firstArchiveDate,
                            lastArchiveDate: payload.lastArchiveDate,
                            selectedRelatedObjects: payload.selectedRelatedObjects || []
                        }
                    ]
                };

                await saveObjectDetailConfiguration({ configJson: JSON.stringify(createPayload) });
            }

            await this.refreshAdminConfiguration();
            this.closeEditModal();
            this.activeTab = 'scheduledJobs';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Job Saved',
                    message: 'Schedule saved successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: this.editModalEntry.recordId ? 'Update Failed' : 'Create Failed',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        }
    }

    async handleDeleteScheduledJob(row) {
        const configId = row && (row.configId || row.id);
        if (!configId) {
            return;
        }

        try {
            await deleteArchiveConfiguration({ configId });
            this.existingScheduledJobs = this.existingScheduledJobs.filter((job) => (job.configId || job.id) !== configId);
            this.objectEntries = this.objectEntries.filter((entry) => (entry.recordId || entry.id) !== configId);
            this.buildScheduledJobsSummary();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Job Deleted',
                    message: 'Scheduled job removed successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Delete Failed',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        }
    }

    handleFieldSelectionChange(event) {
        const entryId = Number(event.target.dataset.id);
        const selectedFields = event.detail && event.detail.value ? event.detail.value : '';

        this.objectEntries = this.objectEntries.map((entry) => {
            if (entry.id !== entryId) {
                return entry;
            }

            return {
                ...entry,
                fieldSetName: selectedFields
            };
        });
    }

    getRelatedObjectsForEntry(entry) {
        if (!entry.objectName || !entry.archiveChildren) {
            return [];
        }
        // Load related objects if not already loaded
        if (!this.relatedObjectsMap[entry.objectName]) {
            this.loadRelatedObjects(entry.objectName);
        }
        return this.relatedObjectsMap?.[entry.objectName] || [];
    }

    hasRelatedObjects(entry) {
        return entry.relatedObjects && entry.relatedObjects.length > 0;
    }

    async loadRelatedObjects(objectName) {
        try {
            const relatedObjects = await getRelatedObjects({ objectName });
            this.relatedObjectsMap = {
                ...this.relatedObjectsMap,
                [objectName]: relatedObjects
            };
        } catch (error) {
            console.error('Failed to load related objects for', objectName, error);
        }
    }

    async loadRelatedObjectsForEntry(entryId, objectName) {
        // Set loading state
        this.objectEntries = this.objectEntries.map(entry => {
            if (entry.id === entryId) {
                return {
                    ...entry,
                    loadingRelatedObjects: true
                };
            }
            return entry;
        });

        try {
            const [masterDetail, lookup] = await Promise.all([
                getRelatedObjects({ objectName }),
                getRelatedLookupObjects({ objectName })
            ]);

            this.relatedObjectsMap = { ...this.relatedObjectsMap, [objectName]: masterDetail };
            this.relatedObjectsLookupMap = { ...this.relatedObjectsLookupMap, [objectName]: lookup };

            this.objectEntries = this.objectEntries.map(entry => {
                if (entry.id === entryId) {
                    return {
                        ...entry,
                        relatedObjects: masterDetail,
                        relatedLookupObjects: lookup,
                        loadingRelatedObjects: false,
                        hasNoRelatedObjects: (masterDetail.length === 0 && lookup.length === 0),
                        // initialize selected lists if missing
                        selectedRelatedObjectsMaster: entry.selectedRelatedObjectsMaster || [],
                        selectedRelatedObjectsLookup: entry.selectedRelatedObjectsLookup || []
                    };
                }
                return entry;
            });
        } catch (error) {
            console.error('Failed to load related objects for entry', entryId, error);
            this.objectEntries = this.objectEntries.map(entry => {
                if (entry.id === entryId) {
                    return {
                        ...entry,
                        relatedObjects: [],
                        relatedLookupObjects: [],
                        loadingRelatedObjects: false,
                        hasNoRelatedObjects: true,
                        selectedRelatedObjectsMaster: entry.selectedRelatedObjectsMaster || [],
                        selectedRelatedObjectsLookup: entry.selectedRelatedObjectsLookup || []
                    };
                }
                return entry;
            });
        }
    }

    handleAddObjectEntry() {
        const newEntry = {
            id: this.nextEntryId,
            objectName: '',
            frequency: '',
            fieldSetName: '',
            isParent: false,
            archiveChildren: false,
            selectedRelatedObjects: [],
            relatedObjects: [],
            relatedLookupObjects: [],
            selectedRelatedObjectsMaster: [],
            selectedRelatedObjectsLookup: [],
            loadingRelatedObjects: false,
            hasNoRelatedObjects: false,
            isExisting: false,
            objectOptions: this.getAvailableObjectOptionsForEntry(this.nextEntryId)
        };

        this.objectEntries = [
            ...this.objectEntries,
            newEntry
        ];
        this.nextEntryId += 1;
    }

    handleRemoveObjectEntry(event) {
        const entryId = Number(event.target.dataset.id);
        this.objectEntries = this.objectEntries.filter((entry) => entry.id !== entryId);
    }

    async handleSave() {
        const forcedRoute = String(this.activeTab || 'objectDetails');
        console.log('[scArchAdminCenter] handleSave route check', {
            activeTab: this.activeTab,
            forcedRoute,
            activeTabType: typeof this.activeTab,
            objectEntriesCount: this.objectEntries ? this.objectEntries.length : 0
        });

        if (forcedRoute === 'quickSchedule') {
            console.log('[scArchAdminCenter] Routing to QUICK_SCHEDULE path via global save');
            await this.handleQuickScheduleSave();
            return;
        }

        console.log('[scArchAdminCenter] Routing to OBJECT_DETAIL path via global save');
        await this.handleObjectDetailSave();
    }

    async handleObjectDetailSave() {
        console.log('[scArchAdminCenter] Explicit OBJECT_DETAIL save triggered');

        if (!this.isNamedCredentialValid) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: 'Please provide a valid named credential before saving.',
                    variant: 'error'
                })
            );
            return;
        }

        const validObjectEntries = this.objectEntries.filter((entry) => entry.objectName).map((entry) => ({
            ...entry,
            fieldSetName: entry.fieldSetName || ''
        }));
        const newOnlyObjectEntries = validObjectEntries.filter((entry) => !entry.isExisting);
        const payload = {
            namedCredential: this.namedCredential,
            clientId: this.clientId,
            clientSecret: this.clientSecret,
            clientName: this.clientName,
            dbHost: this.dbHost,
            dbPort: this.dbPort,
            dbName: this.dbName,
            dbUser: this.dbUser,
            dbPass: this.dbPass,
            sfUsername: this.sfUsername,
            sfToken: this.sfToken,
            sfDomain: this.sfDomain,
            productKey: this.productKey,
            registrationStatus: this.registrationStatus,
            objectEntries: newOnlyObjectEntries
        };

        try {
            console.log('[scArchAdminCenter] Calling Apex saveObjectDetailConfiguration', payload);
            await saveObjectDetailConfiguration({ configJson: JSON.stringify(payload) });
            this.objectEntries = [{
                id: 1,
                objectName: '',
                frequency: '',
                fieldSetName: '',
                isParent: false,
                archiveChildren: false,
                hasDocuments: false,
                firstArchiveDate: '',
                lastArchiveDate: '',
                selectedRelatedObjects: [],
                relatedObjects: [],
                loadingRelatedObjects: false,
                hasNoRelatedObjects: false,
                isExisting: false,
                recordId: null,
                rowKey: null
            }];
            this.nextEntryId = 2;
            await this.refreshAdminConfiguration();
            this.buildScheduledJobsSummary();
            this.activeTab = 'scheduledJobs';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Configuration saved successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error saving configuration',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        }
    }

    async handleQuickScheduleSave() {
        const validEntries = this.objectEntries.filter((entry) => entry.objectName && entry.frequency);
        if (!validEntries.length) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No schedule to save',
                    message: 'Add at least one object with an object name and frequency.',
                    variant: 'error'
                })
            );
            return;
        }

        const payload = {
            objectEntries: validEntries.map((entry) => ({
                id: entry.id,
                objectName: entry.objectName,
                frequency: entry.frequency,
                archiveChildren: entry.archiveChildren === true,
                firstArchiveDate: entry.firstArchiveDate || '',
                lastArchiveDate: entry.lastArchiveDate || '',
                masterRelatedObjects: Array.isArray(entry.selectedRelatedObjectsMaster) ? entry.selectedRelatedObjectsMaster : [],
                lookupRelatedObjects: Array.isArray(entry.selectedRelatedObjectsLookup) ? entry.selectedRelatedObjectsLookup : []
            }))
        };

        try {
            console.log('[scArchAdminCenter] Calling Apex saveQuickSchedule', payload);
            const result = await saveQuickSchedule({ configJson: JSON.stringify(payload) });
            if (result) {
                this.activeTab = 'scheduledJobs';
                await this.refreshAdminConfiguration();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Quick Schedule Submitted',
                        message: 'Archive job request sent successfully.',
                        variant: 'success'
                    })
                );
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Quick Schedule Failed',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        }
    }

    async handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.value;

        this[field] = value;

        if (field === 'namedCredential') {
            await this.validateNamedCredential(value);
        }
    }

    handleClientIdInput(event) {
        this.clientId = event.target.value;
    }

    handleClientSecretInput(event) {
        this.clientSecret = event.target.value;
    }

    async validateNamedCredential(credentialName) {
        if (!credentialName) {
            this.namedCredentialError = '';
            this.isNamedCredentialValid = true;
            return;
        }

        try {
            const isValid = await validateNamedCredential({ credentialName });
            this.isNamedCredentialValid = isValid === true;
            this.namedCredentialError = this.isNamedCredentialValid
                ? ''
                : 'Named credential not found in this org.';
        } catch (error) {
            this.isNamedCredentialValid = false;
            this.namedCredentialError = 'Unable to verify named credential.';
            console.error('Named credential validation failed', error);
        }
    }

    handleCheckboxChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.checked;
    }

    handleDataHostedToggle(event) {
        this.dataHostedToggle = event.target.checked;
    }

    async handleRegisterInstance() {
        if (!this.clientId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Client ID',
                    message: 'Please enter your client ID before registering the instance.',
                    variant: 'error'
                })
            );
            return;
        }

        if (!this.clientSecret) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Client Secret',
                    message: 'Please enter your client secret before registering the instance.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isLoading = true;
        try {
            const result = await registerInstance({
                runtimeKey: this.clientId,
                runtimeToken: this.clientSecret,
                apiVersion: '58.0'
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Instance Registered',
                    message: result.message || 'Instance registration completed successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Registration Failed',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    async handleRegisterOrganization() {
        if (!this.email) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Email',
                    message: 'Please enter your email address.',
                    variant: 'error'
                })
            );
            return;
        }

        // Validate email format
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(this.email)) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invalid Email',
                    message: 'Please enter a valid email address.',
                    variant: 'error'
                })
            );
            return;
        }

        if (!this.firstName) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing First Name',
                    message: 'First name is required for registration.',
                    variant: 'error'
                })
            );
            return;
        }

        if (!this.lastName) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Last Name',
                    message: 'Last name is required for registration.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isLoading = true;
        try {
            const result = await registerOrg({
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                dataHosted: this.dataHostedToggle,
                companyName: this.companyName,
                companyTimeZone: this.timeZone
            });

            this.productKey = result.productKey || '';
            this.registrationStatus = result.registrationStatus || 'Registered';
            this.subscriptionExpiry = result.expiryDate || result.validUntil || '';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Registration Complete',
                    message: result.message || 'Organization registered successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Registration Failed',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    validateProductKey(key) {
        const trimmedKey = key.trim();
        
        // Check if key is blank
        if (!trimmedKey) {
            return { valid: false, message: 'Product key is required.' };
        }
        
        // Check minimum length
        if (trimmedKey.length < 10) {
            return { valid: false, message: 'Product key must be at least 10 characters long.' };
        }
        
        // Check maximum length
        if (trimmedKey.length > 255) {
            return { valid: false, message: 'Product key cannot exceed 255 characters.' };
        }
        
        // Check for valid format (alphanumeric, dots, underscores, and hyphens)
        if (!/^[a-zA-Z0-9._\-]+$/.test(trimmedKey)) {
            return { valid: false, message: 'Product key can only contain letters, numbers, dots, underscores, and hyphens.' };
        }
        
        return { valid: true, message: '' };
    }

    async handleRenewSubscription() {
        // Validate product key format on the UI
        const validation = this.validateProductKey(this.renewalKey);
        if (!validation.valid) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invalid Product Key',
                    message: validation.message,
                    variant: 'error'
                })
            );
            return;
        }

        this.isLoading = true;
        try {
            const result = await renewSubscription({ productKey: this.renewalKey.trim() });
            this.subscriptionStatus = result.registrationStatus || 'Subscription Renewed';
            this.subscriptionLicenseStatus = result.licenseStatus || 'Active';
            this.subscriptionExpiry = result.validUntil || result.expiryDate || result.subscriptionExpiry || this.subscriptionExpiry || '';
            
            // Extract license info from response if available
            const licenseInfo = this.subscriptionLicenseStatus ? ` (Status: ${this.subscriptionLicenseStatus})` : '';
            const validUntil = this.subscriptionExpiry ? ` - Valid until ${this.subscriptionExpiry}` : '';
            
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Renewal Complete',
                    message: `${result.message || 'Renewal product key validated successfully.'}${licenseInfo}${validUntil}`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Renewal Failed',
                    message: error.body ? error.body.message : String(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}
