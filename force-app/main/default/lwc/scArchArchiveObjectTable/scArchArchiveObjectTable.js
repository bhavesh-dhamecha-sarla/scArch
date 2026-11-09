import { LightningElement, wire } from 'lwc';
import getConfigObjectOptions from '@salesforce/apex/ScArchGenericDataTableController.getConfigObjectOptions';
import getPreferredDateField from '@salesforce/apex/ScArchGenericDataTableController.getPreferredDateField';
import getConfiguredFieldNamesForObject from '@salesforce/apex/ScArchGenericDataTableController.getConfiguredFieldNamesForObject';
import getPagedApiData from '@salesforce/apex/ScArchGenericDataTableController.getPagedApiData';

export default class ScArchArchiveObjectTable extends LightningElement {
    objectOptions = [];
    selectedObject = '';
    startDate = '';
    endDate = '';
    isLoading = false;
    errorMessage = '';
    columns = [];
    rows = [];
    page = 1;
    pageSize = 20;
    totalRows = 0;
    hasPrevious = false;
    hasNext = false;
    preferredDateField = 'CreatedDate';

    @wire(getConfigObjectOptions)
    wiredObjectOptions({ error, data }) {
        if (data) {
            this.objectOptions = data.map((item) => ({
                label: item.label || item.value,
                value: item.value
            }));

            if (!this.selectedObject && this.objectOptions.length) {
                this.selectedObject = this.objectOptions[0].value;
            }
        } else if (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load object list.';
        }
    }

    get hasRows() {
        return Array.isArray(this.rows) && this.rows.length > 0;
    }

    get notHasPrevious() {
        return !this.hasPrevious;
    }

    get notHasNext() {
        return !this.hasNext;
    }

    connectedCallback() {
        this.setDefaultDateRange();
    }

    setDefaultDateRange() {
        const today = new Date();
        const from = new Date(today.getTime());
        from.setDate(today.getDate() - 7);
        this.startDate = this.formatDate(from);
        this.endDate = this.formatDate(today);
    }

    formatDate(dateValue) {
        const year = dateValue.getFullYear();
        const month = String(dateValue.getMonth() + 1).padStart(2, '0');
        const day = String(dateValue.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.page = 1;
        this.rows = [];
        this.columns = [];
        this.errorMessage = '';
        this.totalRows = 0;
        this.hasPrevious = false;
        this.hasNext = false;
    }

    handleStartDateChange(event) {
        this.startDate = event.detail.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.detail.value;
    }

    async handleGetData() {
        if (!this.selectedObject) {
            this.errorMessage = 'Please select an object.';
            return;
        }

        if (!this.startDate || !this.endDate) {
            this.errorMessage = 'Please select both start and end dates.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const dateFieldResult = await getPreferredDateField({ objectName: this.selectedObject });
            this.preferredDateField = dateFieldResult || 'CreatedDate';

            const resolvedFields = await getConfiguredFieldNamesForObject({ objectName: this.selectedObject });

            const fieldList = Array.isArray(resolvedFields) && resolvedFields.length > 0
                ? resolvedFields
                : null;

            const dateRange = {
                field: this.preferredDateField,
                from: this.startDate,
                to: this.endDate
            };

            const payload = await getPagedApiData({
                objectName: this.selectedObject,
                endpointPath: '/archive/read/scArchQuery',
                fields: fieldList,
                dateRangeJson: JSON.stringify(dateRange),
                sortJson: JSON.stringify([{ field: this.preferredDateField, direction: 'asc' }]),
                page: this.page,
                pageSize: this.pageSize
            });

            this.columns = payload?.columns || [];
            this.rows = payload?.rows || [];

            const pagination = payload?.pagination || {};
            this.totalRows = Number(pagination.totalRows || 0);
            this.hasPrevious = pagination.hasPrevious === true;
            this.hasNext = pagination.hasNext === true || (this.totalRows > 0 && (Number(pagination.offset || 0) + this.rows.length) < this.totalRows);
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load archive records.';
            this.columns = [];
            this.rows = [];
            this.totalRows = 0;
            this.hasPrevious = false;
            this.hasNext = false;
        } finally {
            this.isLoading = false;
        }
    }

    handlePrevious() {
        if (!this.hasPrevious || this.page <= 1) {
            return;
        }

        this.page -= 1;
        this.handleGetData();
    }

    handleNext() {
        if (!this.hasNext) {
            return;
        }

        this.page += 1;
        this.handleGetData();
    }
}
