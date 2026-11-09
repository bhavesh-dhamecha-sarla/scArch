import { LightningElement, api } from 'lwc';
import getObjectFields from '@salesforce/apex/ScArchAdminController.getObjectFields';

export default class ScArchFieldPicker extends LightningElement {
    _objectName = '';
    _value = '';
    fieldOptions = [];
    selectedFields = [];

    @api
    get objectName() {
        return this._objectName;
    }
    set objectName(value) {
        this._objectName = value || '';
        this.loadFields();
    }

    @api
    get value() {
        return this._value;
    }
    set value(value) {
        this._value = value || '';
        this.selectedFields = this.parseSelectedFields(this._value);
    }

    connectedCallback() {
        this.selectedFields = this.parseSelectedFields(this._value);
    }

    parseSelectedFields(rawValue) {
        if (!rawValue) {
            return [];
        }

        return String(rawValue)
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean);
    }

    async loadFields() {
        if (!this._objectName) {
            this.fieldOptions = [];
            return;
        }

        try {
            const fields = await getObjectFields({ objectName: this._objectName });
            this.fieldOptions = (fields || []).map((item) => ({
                label: item.label || item.value,
                value: item.value
            }));
        } catch (error) {
            this.fieldOptions = [];
            console.error('Failed to load object fields', error);
        }
    }

    handleFieldChange(event) {
        this.selectedFields = event.detail.value || [];
        this._value = this.selectedFields.join(',');
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: this._value }
        }));
    }
}
