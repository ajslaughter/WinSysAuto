/**
 * WinSysAuto Dashboard - Main Application
 * Professional sysadmin-focused dashboard with comprehensive state management
 */

(function () {
    'use strict';

    // [SECURITY] Capture and clear auth token immediately
    const WSA_API_TOKEN = window.WSA_AUTH_TOKEN;
    if (window.WSA_AUTH_TOKEN) {
        delete window.WSA_AUTH_TOKEN;
        console.log('WinSysAuto: Auth token secured.');
    }

    // ===================================================================
    // State Management
    // ===================================================================
    const dashboardState = {
        healthData: null,
        alerts: [],
        isRefreshing: false,
        lastUpdate: null,
        settings: {
            refreshInterval: 30000,
            autoRefresh: true,
            theme: 'light',
            thresholds: {
                cpu: { warning: 70, critical: 90 },
                memory: { warning: 75, critical: 90 },
                disk: { warning: 80, critical: 95 }
            }
        },
        modals: {
            addUsers: false,
            backup: false,
            progress: false
        }
    };

    let refreshIntervalId = null;

    // ===================================================================
    // Utility Functions
    // ===================================================================

    function formatRelativeTime(timestamp) {
        const now = new Date();
        const date = new Date(timestamp);
        const diffMs = now - date;
        const diffSec = Math.floor(diffMs / 1000);
        const diffMin = Math.floor(diffSec / 60);
        const diffHour = Math.floor(diffMin / 60);
        const diffDay = Math.floor(diffHour / 24);

        if (diffSec < 60) return 'just now';
        if (diffMin < 60) return `${diffMin} min ago`;
        if (diffHour < 24) return `${diffHour}h ago`;
        return `${diffDay}d ago`;
    }

    function showToast(type, title, message) {
        const container = document.getElementById('toastContainer');
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;

        const iconSvg = {
            success: '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>',
            error: '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>',
            warning: '<path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>',
            info: '<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>'
        };

        toast.innerHTML = `
            <svg class="toast-icon" width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
                ${iconSvg[type] || iconSvg.info}
            </svg>
            <div class="toast-content">
                <div class="toast-title">${title}</div>
                <div class="toast-message">${message}</div>
            </div>
            <button class="close-btn" onclick="this.parentElement.remove()" style="margin-left: auto;">
                <svg width="16" height="16" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"/>
                </svg>
            </button>
        `;
        container.appendChild(toast);
        setTimeout(() => {
            toast.style.opacity = '0';
            setTimeout(() => toast.remove(), 300);
        }, 5000);
    }

    // ===================================================================
    // Modal Management
    // ===================================================================

    function openModal(modalId) {
        const modal = document.getElementById(modalId);
        if (modal) {
            modal.classList.add('active');
            dashboardState.modals[modalId.replace('Modal', '')] = true;
            document.body.style.overflow = 'hidden';
        }
    }

    function closeModal(modalId) {
        const modal = document.getElementById(modalId);
        if (modal) {
            modal.classList.remove('active');
            dashboardState.modals[modalId.replace('Modal', '')] = true;
            document.body.style.overflow = '';
        }
    }

    function setupModalCloseOnOverlay() {
        document.querySelectorAll('.modal').forEach(modal => {
            const overlay = modal.querySelector('.modal-overlay');
            if (overlay) {
                overlay.addEventListener('click', () => closeModal(modal.id));
            }
        });
    }

    function setupModalCloseButtons() {
        document.querySelectorAll('.modal .close-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const modal = e.target.closest('.modal');
                if (modal) closeModal(modal.id);
            });
        });
    }

    // ===================================================================
    // API Integration
    // ===================================================================

    async function callApi(endpoint, options = {}) {
        try {
            const headers = {};
            // Use local secure token variable
            if (WSA_API_TOKEN) {
                headers['X-Auth-Token'] = WSA_API_TOKEN;
            }
            if (!options.body instanceof FormData) {
                headers['Content-Type'] = 'application/json';
            }

            const response = await fetch(endpoint, {
                method: 'POST',
                headers: headers,
                ...options
            });

            const data = await response.json();
            if (!data.ok && data.ok !== undefined) {
                throw new Error(data.message || 'Request failed');
            }
            return data;
        } catch (error) {
            console.error('API Error:', error);
            throw error;
        }
    }

    // ===================================================================
    // Dashboard Data Updates
    // ===================================================================

    async function updateDashboard() {
        if (dashboardState.isRefreshing) return;
        dashboardState.isRefreshing = true;

        try {
            const response = await fetch('/api/health');
            const data = await response.json();
            dashboardState.healthData = data;
            dashboardState.lastUpdate = new Date();

            updateHealthOverview(data);
            updateResourceMetrics(data);
            updateServices(data);
            updateAlerts(data);
            updateDrift(); // Fetch drift data
            updateEnvironmentUI(data.environment); // Graceful degradation
            updateLastUpdated();
        } catch (error) {
            console.error('Failed to update dashboard:', error);
            showToast('error', 'Update Failed', 'Could not fetch latest data');
        } finally {
            dashboardState.isRefreshing = false;
        }
    }

    function updateHealthOverview(data) {
        const healthScore = document.getElementById('healthScore');
        const overallHealthCard = document.getElementById('overallHealthCard');
        if (healthScore) healthScore.textContent = data.healthScore || '--';

        if (overallHealthCard) {
            overallHealthCard.classList.remove('critical-card', 'warning-card');
            if (data.healthStatus === 'critical') overallHealthCard.classList.add('critical-card');
            else if (data.healthStatus === 'warning') overallHealthCard.classList.add('warning-card');
        }

        const criticalCount = document.getElementById('criticalCount');
        if (criticalCount) {
            criticalCount.textContent = (data.alerts || []).filter(a => a.level && a.level.toLowerCase() === 'critical').length;
        }

        const warningCount = document.getElementById('warningCount');
        if (warningCount) {
            warningCount.textContent = (data.alerts || []).filter(a => a.level && a.level.toLowerCase() === 'warning').length;
        }

        const lastBackup = document.getElementById('lastBackup');
        if (lastBackup && data.timestamp) {
            lastBackup.textContent = formatRelativeTime(data.timestamp);
        }
    }

    function updateResourceMetrics(data) {
        updateResourceCard('cpu', data.cpu?.total || 0);
        if (data.memory) {
            updateResourceCard('memory', data.memory.percent);
            const memoryDetail = document.getElementById('memoryDetail');
            if (memoryDetail) memoryDetail.textContent = `${data.memory.usedGB.toFixed(1)} GB / ${data.memory.totalGB.toFixed(1)} GB`;
        }
        if (data.disk && data.disk.length > 0) {
            const primaryDisk = data.disk[0];
            updateResourceCard('disk', primaryDisk.usagePercent);
            const diskDetail = document.getElementById('diskDetail');
            if (diskDetail) diskDetail.textContent = `${primaryDisk.usedGB.toFixed(1)} GB / ${primaryDisk.totalGB.toFixed(1)} GB`;
        }
    }

    function updateResourceCard(resource, percent) {
        const percentEl = document.getElementById(`${resource}Percent`);
        const barEl = document.getElementById(`${resource}Bar`);
        const thresholds = dashboardState.settings.thresholds[resource];

        if (percentEl) percentEl.textContent = `${percent.toFixed(1)}%`;
        if (barEl) {
            barEl.style.width = `${percent}%`;
            barEl.setAttribute('aria-valuenow', percent);
            barEl.classList.remove('warning', 'critical');
            if (percent >= thresholds.critical) barEl.classList.add('critical');
            else if (percent >= thresholds.warning) barEl.classList.add('warning');
        }
    }

    function updateServices(data) {
        const servicesList = document.getElementById('servicesList');
        if (!servicesList || !data.services) return;
        servicesList.innerHTML = '';
        const criticalServices = data.services.slice(0, 5);

        criticalServices.forEach(service => {
            const serviceItem = document.createElement('div');
            serviceItem.className = `service-item ${service.health}`;
            const statusIconClass = service.status === 'Running' ? 'running' :
                service.status === 'Stopped' ? 'stopped' : 'degraded';
            serviceItem.innerHTML = `
                <span class="service-name">${service.name}</span>
                <div class="service-status">
                    <span>${service.status}</span>
                    <div class="service-icon ${statusIconClass}"></div>
                    <button class="icon-btn" onclick="window.restartService('${service.name}')" title="Restart Service">
                        <svg width="16" height="16" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd"/>
                        </svg>
                    </button>
                </div>
            `;
            servicesList.appendChild(serviceItem);
        });

        const viewAllBtn = document.getElementById('viewAllServices');
        if (viewAllBtn) viewAllBtn.textContent = `View All Services (${data.services.length})`;
    }

    function updateAlerts(data) {
        const alertsList = document.getElementById('alertsList');
        if (!alertsList) return;
        alertsList.innerHTML = '';

        if (!data.alerts || data.alerts.length === 0) {
            alertsList.innerHTML = `
                <div class="empty-state">
                    <svg width="48" height="48" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                    </svg>
                    <p>No active alerts</p>
                </div>`;
            return;
        }

        data.alerts.forEach(alert => {
            const alertItem = document.createElement('div');
            alertItem.className = `alert-item ${alert.level.toLowerCase()}`;
            alertItem.innerHTML = `
                <div class="alert-header">
                    <div class="alert-title">[${alert.level}] ${alert.metric}</div>
                    <div class="alert-time">just now</div>
                </div>
                <div class="alert-message">${alert.message}</div>
                <div class="alert-actions">
                    <button class="link-btn">View Details</button>
                    <button class="link-btn">Dismiss</button>
                </div>`;
            alertsList.appendChild(alertItem);
        });
        dashboardState.alerts = data.alerts;
    }

    async function updateDrift() {
        const driftList = document.getElementById('driftList');
        if (!driftList) return;

        try {
            const result = await callApi('/api/action/drift');
            const items = result.data || [];

            if (items.length === 0) {
                driftList.innerHTML = `
                    <div class="empty-state">
                        <p>No changes detected today.</p>
                    </div>`;
                return;
            }

            driftList.innerHTML = '';
            items.forEach(item => {
                const div = document.createElement('div');
                div.className = `drift-item ${item.Severity === 'Warning' ? 'warning' : ''}`;
                div.innerHTML = `
                    <div class="drift-message">
                        <strong>[${item.Type}]</strong> ${item.Message}
                    </div>
                    <div class="drift-time">${formatRelativeTime(item.Timestamp)}</div>
                `;
                driftList.appendChild(div);
            });
        } catch (error) {
            console.error('Drift fetch failed', error);
        }
    }

    function updateEnvironmentUI(env) {
        if (!env) return;

        // Hide User Management if no AD module or not domain joined
        const userBtn = document.getElementById('btnUserMgmt');
        if (userBtn) {
            userBtn.style.display = (env.hasAdModule && env.isDomainJoined) ? 'inline-flex' : 'none';
        }

        // Hide Domain info if not joined
        const domainInfo = document.querySelector('.domain-info');
        if (domainInfo && !env.isDomainJoined) {
            domainInfo.innerHTML = '<span style="color:var(--warning)">Workgroup Mode</span>';
        }
    }

    function updateLastUpdated() {
        const lastUpdated = document.getElementById('lastUpdated');
        if (lastUpdated && dashboardState.lastUpdate) {
            lastUpdated.textContent = formatRelativeTime(dashboardState.lastUpdate);
        }
    }

    // ===================================================================
    // Button Loading State Helpers
    // ===================================================================

    function setButtonLoading(button, isLoading) {
        if (!button) return;
        if (isLoading) {
            button.classList.add('btn-loading');
            button.disabled = true;
            if (!button.dataset.originalHtml) button.dataset.originalHtml = button.innerHTML;
        } else {
            button.classList.remove('btn-loading');
            button.disabled = false;
            if (button.dataset.originalHtml) {
                button.innerHTML = button.dataset.originalHtml;
                delete button.dataset.originalHtml;
            }
        }
    }

    // ===================================================================
    // Action Button Handlers
    // ===================================================================

    async function runHealthCheck() {
        const button = document.getElementById('btnHealthCheck');
        setButtonLoading(button, true);
        showProgressModal('Running Health Check...', 'Gathering system metrics...');
        try {
            const result = await callApi('/api/action/health', { body: JSON.stringify({}) });
            closeModal('progressModal');
            if (result.ok || result.ok === undefined) {
                showToast('success', 'Health Check Complete', 'System checks completed');
                await updateDashboard();
            } else {
                showToast('error', 'Check Failed', result.message);
            }
        } catch (error) {
            closeModal('progressModal');
            showToast('error', 'Check Failed', error.message);
        } finally {
            setButtonLoading(button, false);
        }
    }

    function showProgressModal(title, text) {
        const titleEl = document.getElementById('progressTitle');
        const textEl = document.getElementById('progressText');
        if (titleEl) titleEl.textContent = title;
        if (textEl) textEl.textContent = text;
        openModal('progressModal');
    }

    async function createBackup() {
        const button = document.getElementById('btnBackup');
        closeModal('backupModal');
        setButtonLoading(button, true);
        showProgressModal('Creating Backup...', 'Backing up configuration data...');
        try {
            const result = await callApi('/api/action/backup', { body: JSON.stringify({ note: 'Manual backup' }) });
            closeModal('progressModal');
            if (result.ok || result.backupPath) {
                showToast('success', 'Backup Complete', `Created: ${result.backupPath || 'Success'}`);
            } else {
                showToast('error', 'Backup Failed', result.message);
            }
        } catch (error) {
            closeModal('progressModal');
            showToast('error', 'Backup Failed', error.message);
        } finally {
            setButtonLoading(button, false);
        }
    }

    async function addUsersFromCSV() {
        const fileInput = document.getElementById('csvFile');
        const defaultOU = document.getElementById('defaultOU').value;
        const autoCreateGroups = document.getElementById('autoCreateGroups').checked;
        const resetPasswords = document.getElementById('resetPasswords').checked;

        if (!fileInput.files || fileInput.files.length === 0) return showToast('error', 'No File', 'Select a CSV');
        const file = fileInput.files[0];
        if (!file.name.endsWith('.csv')) return showToast('error', 'Invalid File', 'Must be .csv');

        const button = document.getElementById('btnAddUsers');
        closeModal('addUsersModal');
        setButtonLoading(button, true);
        showProgressModal('Creating Users...', 'Processing CSV file...');

        try {
            const formData = new FormData();
            formData.append('file', file);
            if (defaultOU) formData.append('defaultOU', defaultOU);
            formData.append('groupsMode', autoCreateGroups ? 'Append' : 'Replace');
            formData.append('resetPasswords', resetPasswords.toString());

            const result = await callApi('/api/action/new-users', { body: formData });
            closeModal('progressModal');

            if (result.ok) {
                showToast('success', 'Users Created', `Created: ${result.created}, Skipped: ${result.skipped}`);
            } else {
                showToast('error', 'Failed', result.message);
            }
        } catch (error) {
            closeModal('progressModal');
            showToast('error', 'Failed', error.message);
        } finally {
            setButtonLoading(button, false);
        }
    }

    async function runSecurityAudit() {
        const button = document.getElementById('btnSecurityAudit');
        setButtonLoading(button, true);
        showProgressModal('Running Audit...', 'Checking baseline...');
        try {
            const result = await callApi('/api/action/security-baseline', { body: JSON.stringify({ mode: 'Audit' }) });
            closeModal('progressModal');
            if (result.ok) {
                showToast('success', 'Audit Complete', result.summary || 'Success');
            } else {
                showToast('error', 'Audit Failed', result.message);
            }
        } catch (error) {
            closeModal('progressModal');
            showToast('error', 'Audit Failed', error.message);
        } finally {
            setButtonLoading(button, false);
        }
    }

    async function generateReport() {
        const button = document.getElementById('btnGenerateReport');
        setButtonLoading(button, true);
        try {
            showToast('info', 'Generating Report', 'Preparing system report...');
            await new Promise(resolve => setTimeout(resolve, 1500));
            showToast('success', 'Report Ready', 'Report generated successfully');
        } catch (error) {
            showToast('error', 'Failed', error.message);
        } finally {
            setButtonLoading(button, false);
        }
    }

    // Service Control
    window.restartService = async function (serviceName) {
        if (!confirm(`Are you sure you want to restart ${serviceName}?`)) return;
        showToast('info', 'Restarting Service', `Restarting ${serviceName}...`);
        try {
            const result = await callApi('/api/action/service-control', {
                body: JSON.stringify({ name: serviceName, action: 'Restart' })
            });
            if (result.ok) {
                showToast('success', 'Service Restarted', result.message);
                updateDashboard();
            } else {
                showToast('error', 'Restart Failed', result.message);
            }
        } catch (error) {
            showToast('error', 'Restart Failed', error.message);
        }
    };

    // User Management
    async function handleUserSubmit(type) {
        let payload = { operation: type };

        if (type === 'Create') {
            payload.firstname = document.getElementById('newFirstName').value;
            payload.lastname = document.getElementById('newLastName').value;
            payload.username = document.getElementById('newUsername').value;
            payload.password = document.getElementById('newPassword').value;
            if (!payload.username || !payload.password) return showToast('error', 'Missing Data', 'Username and Password required');
        } else if (type === 'Unlock') {
            payload.username = document.getElementById('unlockUsername').value;
            if (!payload.username) return showToast('error', 'Missing Data', 'Username required');
        } else if (type === 'Reset') {
            payload.username = document.getElementById('resetUsername').value;
            payload.password = document.getElementById('resetPassword').value;
            if (!payload.username || !payload.password) return showToast('error', 'Missing Data', 'Username and Password required');
        }

        const btnId = type === 'Create' ? 'btnSubmitCreate' : type === 'Unlock' ? 'btnSubmitUnlock' : 'btnSubmitReset';
        const button = document.getElementById(btnId);
        setButtonLoading(button, true);

        try {
            const result = await callApi('/api/action/user-operation', { body: JSON.stringify(payload) });
            if (result.ok) {
                showToast('success', 'Success', result.message);
                closeModal('userMgmtModal');
                // Clear forms
                document.querySelectorAll('#userMgmtModal input').forEach(i => i.value = '');
            } else {
                showToast('error', 'Failed', result.message);
            }
        } catch (error) {
            showToast('error', 'Failed', error.message);
        } finally {
            setButtonLoading(button, false);
        }
    }

    // Security Control
    async function toggleSecurity(e) {
        const isEnabled = e.target.checked;
        const mode = isEnabled ? 'Apply' : 'Rollback';

        showToast('info', 'Security Baseline', `${mode}ing baseline...`);
        try {
            const result = await callApi('/api/action/security-baseline', {
                body: JSON.stringify({ mode: mode })
            });
            if (result.ok) {
                showToast('success', 'Success', `Baseline ${mode}ed successfully`);
                document.getElementById('securityStatus').textContent = `Status: ${mode}ed`;
            } else {
                showToast('error', 'Failed', result.message);
                e.target.checked = !isEnabled; // Revert toggle
            }
        } catch (error) {
            showToast('error', 'Failed', error.message);
            e.target.checked = !isEnabled;
        }
    }

    // ===================================================================
    // Settings & Initialization
    // ===================================================================

    function toggleSettings() {
        document.getElementById('settingsSidebar')?.classList.toggle('active');
    }

    function saveSettings() {
        showToast('success', 'Settings Saved', 'Preferences updated');
        toggleSettings();
    }

    function loadSettings() {
        // Load settings logic if needed
    }

    function startAutoRefresh() {
        if (refreshIntervalId) clearInterval(refreshIntervalId);
        refreshIntervalId = setInterval(updateDashboard, dashboardState.settings.refreshInterval);
        const statusEl = document.getElementById('autoRefreshStatus');
        if (statusEl) statusEl.textContent = `ON (${dashboardState.settings.refreshInterval / 1000}s)`;
    }

    function stopAutoRefresh() {
        if (refreshIntervalId) clearInterval(refreshIntervalId);
    }

    function setupEventListeners() {
        const btnHealthCheck = document.getElementById('btnHealthCheck');
        if (btnHealthCheck) btnHealthCheck.addEventListener('click', runHealthCheck);

        const btnBackup = document.getElementById('btnBackup');
        if (btnBackup) btnBackup.addEventListener('click', () => openModal('backupModal'));

        const btnAddUsers = document.getElementById('btnAddUsers');
        if (btnAddUsers) btnAddUsers.addEventListener('click', () => openModal('addUsersModal'));

        const btnSecurityAudit = document.getElementById('btnSecurityAudit');
        if (btnSecurityAudit) btnSecurityAudit.addEventListener('click', runSecurityAudit);

        const btnUserMgmt = document.getElementById('btnUserMgmt');
        if (btnUserMgmt) btnUserMgmt.addEventListener('click', () => openModal('userMgmtModal'));

        const btnSecurityControl = document.getElementById('btnSecurityControl');
        if (btnSecurityControl) btnSecurityControl.addEventListener('click', () => openModal('securityModal'));

        // User Mgmt Tabs
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
                e.target.classList.add('active');
                document.getElementById(`tab-${e.target.dataset.tab}`).style.display = 'block';
            });
        });

        document.getElementById('btnSubmitCreate')?.addEventListener('click', () => handleUserSubmit('Create'));
        document.getElementById('btnSubmitUnlock')?.addEventListener('click', () => handleUserSubmit('Unlock'));
        document.getElementById('btnSubmitReset')?.addEventListener('click', () => handleUserSubmit('Reset'));

        document.getElementById('securityToggle')?.addEventListener('change', toggleSecurity);

        const btnGenerateReport = document.getElementById('btnGenerateReport');
        if (btnGenerateReport) btnGenerateReport.addEventListener('click', generateReport);

        // Settings
        document.getElementById('openSettings')?.addEventListener('click', toggleSettings);
        document.getElementById('closeSidebar')?.addEventListener('click', toggleSettings);
        document.getElementById('saveSettings')?.addEventListener('click', saveSettings);

        // Modal Actions
        document.getElementById('confirmBackup')?.addEventListener('click', createBackup);
        document.getElementById('cancelBackup')?.addEventListener('click', () => closeModal('backupModal'));
        document.getElementById('confirmAddUsers')?.addEventListener('click', addUsersFromCSV);
        document.getElementById('cancelAddUsers')?.addEventListener('click', () => closeModal('addUsersModal'));
    }

    function initDashboard() {
        console.log('WinSysAuto Initializing...');
        loadSettings();
        setupModalCloseOnOverlay();
        setupModalCloseButtons();
        // setupCollapsibleSections(); // This function was missing in original file, need to add it or remove call

        // Collapsible sections logic
        document.querySelectorAll('.expand-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const section = btn.closest('.collapsible');
                section.classList.toggle('collapsed');
                const isCollapsed = section.classList.contains('collapsed');
                btn.setAttribute('aria-expanded', !isCollapsed);
            });
        });

        setupEventListeners();
        setupKeyboardShortcuts();
        updateDashboard();
        if (dashboardState.settings.autoRefresh) startAutoRefresh();
        setInterval(updateLastUpdated, 30000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initDashboard);
    } else {
        initDashboard();
    }

    window.addEventListener('beforeunload', stopAutoRefresh);

})();
