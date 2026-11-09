import { LightningElement, api } from 'lwc';
import getPagedApiData from '@salesforce/apex/ScArchGenericDataTableController.getPagedApiData';
import getFieldNamesForFieldSet from '@salesforce/apex/ScArchGenericDataTableController.getFieldNamesForFieldSet';

export default class ScArchGenericDataTable extends LightningElement {
    _objectName = 'InContact_Call_Log__c';
    _endpointPath = '/archive/read/scArchQuery';
    _fieldSetName = '';
    _dateRangeJson = '';
    _sortJson = '[{"field":"Id","direction":"asc"}]';
    _pageSize = 20;
    _title = 'Archived Data';
    _refresh = false;

    @api
    get objectName() {
        return this._objectName;
    }
    set objectName(value) {
        this._objectName = value || this._objectName;
    }

    @api
    get endpointPath() {
        return this._endpointPath;
    }
    set endpointPath(value) {
        this._endpointPath = value || this._endpointPath;
    }

    @api
    get fieldSetName() {
        return this._fieldSetName;
    }
    set fieldSetName(value) {
        this._fieldSetName = value || '';
    }

    @api
    get dateRangeJson() {
        return this._dateRangeJson;
    }
    set dateRangeJson(value) {
        this._dateRangeJson = value || '';
    }

    @api
    get sortJson() {
        return this._sortJson;
    }
    set sortJson(value) {
        this._sortJson = value || '[{"field":"Id","direction":"asc"}]';
    }

    @api
    get pageSize() {
        return this._pageSize;
    }
    set pageSize(value) {
        const normalized = Number(value);
        this._pageSize = Number.isFinite(normalized) && normalized > 0 ? normalized : 20;
        if (this.page === 1) {
            this.page = 1;
        }
    }

    @api
    get title() {
        return this._title;
    }
    set title(value) {
        this._title = value || this._title;
    }

    @api
    get refresh() {
        return this._refresh;
    }
    set refresh(value) {
        this._refresh = value === true;
        if (this._refresh) {
            this.refreshData();
        }
    }

    columns = [];
    rows = [];
    page = 1;
    isLoading = false;
    errorMessage = '';
    pagination = {};
    isInitialized = false;
    fieldNames = [];
    isRefreshInProgress = false;
    pendingRefresh = false;
    requestSequence = 0;

    connectedCallback() {
        this.isInitialized = true;
        this._pageSize = 20;
        this.setDefaultDateRange();
    }

    get hasRows() {
        return Array.isArray(this.rows) && this.rows.length > 0;
    }

    get hasPrevious() {
        return this.pagination && this.pagination.hasPrevious === true;
    }

    get notHasPrevious() {
        return !(this.hasPrevious);
    }

    get hasNext() {
        if (!this.pagination) {
            return false;
        }
        if (this.pagination.hasNext === true) {
            return true;
        }

        const totalRows = Number(this.pagination.totalRows || 0);
        const currentOffset = Number(this.pagination.offset || 0);
        const rowCount = Array.isArray(this.rows) ? this.rows.length : 0;

        if (totalRows > 0) {
            return (currentOffset + rowCount) < totalRows;
        }

        return false;
    }

    get totalRows() {
        return Number(this.pagination?.totalRows || 0);
    }

    get notHasNext() {
        return !(this.hasNext);
    }

    get fieldList() {
        return this.fieldNames;
    }

    get dateFrom() {
        try {
            const parsed = JSON.parse(this._dateRangeJson || '{}');
            return parsed.from || '';
        } catch (error) {
            return '';
        }
    }

    get dateTo() {
        try {
            const parsed = JSON.parse(this._dateRangeJson || '{}');
            return parsed.to || '';
        } catch (error) {
            return '';
        }
    }

    setDefaultDateRange() {
        const today = new Date();
        const from = new Date(today.getTime());
        from.setDate(today.getDate() - 7);
        const formatDate = (dateValue) => {
            const year = dateValue.getFullYear();
            const month = String(dateValue.getMonth() + 1).padStart(2, '0');
            const day = String(dateValue.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        };

        this._dateRangeJson = JSON.stringify({
            field: 'Id',
            from: formatDate(from),
            to: formatDate(today)
        });
    }

    refreshDataIfReady() {
        if (!this.isInitialized) {
            return;
        }
        this.page = 1;
    }

    async triggerLoad() {
        if (this.isRefreshInProgress) {
            this.pendingRefresh = true;
            return;
        }

        this.isRefreshInProgress = true;
        try {
            await this.resolveFieldNames();
            await this.loadData();
        } finally {
            this.isRefreshInProgress = false;
            if (this.pendingRefresh) {
                this.pendingRefresh = false;
                this.triggerLoad();
            }
        }
    }

    async resolveFieldNames() {
        if (!this.objectName) {
            this.fieldNames = [];
            return;
        }

        try {
            const resolvedFields = await getFieldNamesForFieldSet({
                objectName: this.objectName,
                fieldSetName: this.fieldSetName
            });
            this.fieldNames = Array.isArray(resolvedFields) ? resolvedFields : [];
        } catch (error) {
            this.fieldNames = [];
            this.errorMessage = error?.body?.message || error?.message || 'Unable to resolve field set fields.';
        }
    }

    async loadData() {
        const requestId = ++this.requestSequence;
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const result = await getPagedApiData({
                objectName: this.objectName,
                endpointPath: this.endpointPath,
                fields: this.fieldList,
                dateRangeJson: this.dateRangeJson,
                sortJson: this.sortJson,
                page: this.page,
                pageSize: this.pageSize
            });

            if (requestId !== this.requestSequence) {
                return;
            }

            this.columns = result?.columns || [];
            this.rows = result?.rows || [];
            this.pagination = result?.pagination || {};
        } catch (error) {
            if (requestId !== this.requestSequence) {
                return;
            }

            this.errorMessage = error?.body?.message || error?.message || 'Unable to load records.';
            this.columns = [];
            this.rows = [];
            this.pagination = {};
        } finally {
            if (requestId === this.requestSequence) {
                this.isLoading = false;
            }
        }
    }

    handlePrevious() {
        if (this.page > 1) {
            this.page -= 1;
            this.loadData();
        }
    }

    handleNext() {
        if (!this.hasNext) {
            return;
        }
        this.page += 1;
        this.loadData();
    }

    refreshData() {
        this.page = 1;
        this.triggerLoad();
    }

    handleGetData() {
        this.page = 1;
        this.triggerLoad();
    }

    handleDateFromChange(event) {
        this.updateDateRange('from', event.target.value);
    }

    handleDateToChange(event) {
        this.updateDateRange('to', event.target.value);
    }

    updateDateRange(key, value) {
        if (!this._dateRangeJson) {
            this.setDefaultDateRange();
        }

        const parsed = JSON.parse(this._dateRangeJson || '{}');
        parsed.field = parsed.field || 'Id';
        if (value) {
            parsed[key] = value;
        }
        this._dateRangeJson = JSON.stringify(parsed);
    }
}
