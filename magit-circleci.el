;;; magit-circleci.el --- CircleCI integration for Magit -*- lexical-binding: t; -*-

;; Copyright (C) 2019, Quan Nguyen

;; This file is NOT part of Emacs.

;; This  program is  free  software; you  can  redistribute it  and/or
;; modify it  under the  terms of  the GNU  General Public  License as
;; published by the Free Software  Foundation; either version 2 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT  ANY  WARRANTY;  without   even  the  implied  warranty  of
;; MERCHANTABILITY or FITNESS  FOR A PARTICULAR PURPOSE.   See the GNU
;; General Public License for more details.

;; You should have  received a copy of the GNU  General Public License
;; along  with  this program;  if  not,  write  to the  Free  Software
;; Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
;; USA

;; Version: 1.0
;; Author: Quan Nguyen
;; Keywords: circleci continuous integration magit vc tools
;; URL: https://github.com/abrochard/magit-circleci
;; License: GNU General Public License >= 3
;; Package-Requires: ((dash "2.16.0") (transient "0.1.0") (magit "2.90.0") (emacs "28.2"))

;;; Commentary:

;; Magit extension to integrate with CircleCI.
;; See the latest builds from the magit status buffer.

;;; Setup:

;; Get your token (https://circleci.com/docs/api/#add-an-api-token)
;; and shove it as (setq magit-circleci-token "XXXXXXXX")
;; or set it as environment variable CIRCLECI_TOKEN

;;; Usage:

;; M-x magit-circleci-mode : to activate
;; C-c C-o OR RET : to visit the build at point
;; " : in magit status to open the CircleCI Menu
;; " f : to pull latest builds for the current repo

;;; Code:

(require 'json)
(require 'url-http)
(require 'magit)
(require 'transient)
(require 'dash)

;; Define the variables
(defvar url-http-end-of-headers)  ; silence byte-compiler warnings

(defgroup magit-circleci nil
  "CircleCI integration for Magit."
  :group 'extensions
  :group 'tools
  :link '(url-link :tag "Repository" ""))

(defcustom magit-circleci-host "https://circleci.com"
  "CircleCI API host."
  :group 'magit-circleci
  :type 'string)

(defvar magit-circleci-token
  ;; CircleCI Token
  (getenv "CIRCLECI_TOKEN"))

(defvar magit-circleci-organisation-name
  ;; CircleCI Organisation name
  (getenv "CIRCLECI_ORGANISATION_NAME"))

(defvar magit-circleci--project-slug
  ;; CircleCI Project Slug
  (concat "gh/" magit-circleci-organisation-name))

(defvar magit-circleci--cache nil) ;; Store cache data

;; Define the functions
(defun magit-circleci--reponame ()
  "Get the name of the current repo."
  (concat magit-circleci--project-slug "/" (file-name-nondirectory (directory-file-name (magit-toplevel)))))

(defun magit-circleci--current-branch ()
  "Get the current branch of project"
  (magit-get-current-branch))

(defun magit-circleci--repo-has-config ()
  "Look if current repo has a circle config."
  (file-exists-p (concat (magit-toplevel) ".circleci/config.yml")))

;; Handle API request
(defun magit-circleci--request (method endpoint &rest args)
  "Make a request to the circleCI API.
METHOD is the request mothod.
ENDPOINT is the endpoint.
ARGS is the url arguments."
  (let ((url (concat magit-circleci-host "/api/v2" endpoint
                     "?circle-token=" magit-circleci-token
                     "&" (mapconcat #'identity args "&")))
        (url-request-method method)
        (url-request-extra-headers '(("Accept" . "application/json"))))
    (with-current-buffer (url-retrieve-synchronously url)
      (goto-char url-http-end-of-headers)
      (json-read)))) ;; TODO: utf-8 support

(defun magit-circleci--project-detail ()
  "Get project details"
  (let ((project-detail (magit-circleci--request "GET" (concat "/project/" (magit-circleci--reponame)))))
    (list (assoc 'slug project-detail)
          (assoc 'name project-detail)
          (assoc 'organization_slug project-detail)
          (assoc 'vcs_url (assoc 'vcs_info project-detail)))))

(defun magit-circleci--recent-pipeline ()
  "Get the latest pipeline"
  (let* ((recent-pipeline (magit-circleci--request "GET" (concat "/project/" (magit-circleci--reponame) "/pipeline") (concat "branch=" (magit-circleci--current-branch))))
         (items (cdr (assoc 'items recent-pipeline))))
    (aref items 0)))

(defun magit-circleci--pipeline-workflow ()
  "Get the pipeline with the workflow id"
  (let* ((pipeline-detail (magit-circleci--recent-pipeline))
         (pipeline-id (cdr (assoc 'id pipeline-detail)))
         (workflow-detail (magit-circleci--request "GET" (concat "/pipeline/" pipeline-id "/workflow"))))
    (cdr (assoc 'items workflow-detail))))

(defun magit-circleci--workflow-detail (item)
  "Build workflow detail"
  (let* ((workflow-id (cdr (assoc 'id item)))
         (workflow-name (cdr (assoc 'name item)))
         (workflow-status (cdr (assoc 'status item)))
         (pipeline-number (cdr (assoc 'pipeline_number item)))
         (workflow-job (magit-circleci--request "GET" (concat "/workflow/" workflow-id "/job")))
         (workflow-job-items (cdr (assoc 'items workflow-job)))
         (current-branch (magit-circleci--current-branch))
         (details (list (cons "workflow_id" workflow-id)
                        (cons "workflow_name" workflow-name)
                        (cons "workflow_status" workflow-status)
                        (cons "pipeline_number" pipeline-number)
                        (cons "branch" current-branch))))
    (push (cons "items" workflow-job-items) details)))

(defun magit-circleci--recent-workflow-jobs ()
  "Get the workflow jobs"
  (let ((workflow-detail (magit-circleci--pipeline-workflow)))
    (mapcar
     (lambda (item)
       (magit-circleci--workflow-detail item))
     workflow-detail)))

;; Dispatch the actions
(defun magit-circleci-pull ()
  "Pull last builds of current repo and put them in cache."
  (interactive)
  (when (magit-circleci--repo-has-config)
    (let ((project (magit-circleci--project-detail)))
      (when project
        (let ((project-name (cdr (assoc 'name project))))
          (magit-circleci--update-cache project-name (magit-circleci--recent-workflow-jobs))
          (message "Done")
          (magit))))))

(defun magit-circleci--build-job-url (pipeline-number workflow-id job-id approval-request-id)
  (cond ((not (equal approval-request-id nil)) (concat (format "/workflow/%s" workflow-id)
                                                       (format "/approve/%s" approval-request-id)))
        (t (concat "https://app.circleci.com/pipelines/github/"
                   (string-replace "gh/" "" (magit-circleci--reponame))
                   (format "/%s/workflows/" pipeline-number)
                   workflow-id
                   (if (equal job-id nil) "" (format "/jobs/%s" job-id))))))


(defun magit-circleci--find-build-filter-workflow (workflow-name data)
  "Filter the workflow by the workflow name."
  (let* ((workflow-filter-name (cond ((string-match-p "approve" workflow-name) (car (split-string workflow-name " - ")))
                                     (t (cadr (split-string workflow-name " - ")))))
         (workflow (car (seq-filter (lambda (item) (equal (cdr (assoc 'name item)) workflow-filter-name)) (cdr (assoc "items" data)))))
         (pipeline-number (assoc "pipeline_number" data))
         (workflow-id (assoc "workflow_id" data))
         (result '()))

    (if (equal workflow nil)
        (setq result nil)
      (progn
        (push workflow-id result)
        (push pipeline-number result)
        (push workflow result)))
    result))

(defun magit-circleci--find-build-get-workflow (data job-name)
  "Get the workflow detail."
  (seq-map (lambda (item) (magit-circleci--find-build-filter-workflow job-name item)) data))

(defun magit-circleci--find-build-get-workflow-items (data)
  "Get the list of workflow."
  (seq-map (lambda (item) (let* ((items (assoc "items" item))
                                 (pipeline-number (assoc "pipeline_number" item))
                                 (workflow-id (assoc "workflow_id" item))
                                 (result '()))
                            (push items result)
                            (push pipeline-number result)
                            (push workflow-id result)
                            result)) data))

(defun magit-circleci--find-build (job-name)
  "Find the specific build from cache.
REPO is the repo name.
BUILD-NUM is the build number."
  (let* ((workflow-data (cdr (assoc (magit-circleci--current-branch) (magit-circleci--read-cache-file))))
         (workflow-items (magit-circleci--find-build-get-workflow-items workflow-data))
         (jobs (magit-circleci--find-build-get-workflow workflow-items job-name))
         (current-job (car (seq-filter (lambda (job) (not (equal job nil))) jobs)))
         (pipeline-number (cdr (assoc "pipeline_number" current-job)))
         (workflow-id (cdr (assoc "workflow_id" current-job)))
         (job-number (cdr (assoc 'job_number (car current-job))))
         (approval-request-id (cdr (assoc 'approval_request_id (car current-job)))))
    (magit-circleci--build-job-url pipeline-number workflow-id job-number approval-request-id)))


(defun magit-circleci-browse-build ()
  "Browse build under cursor."
  (interactive)
  (let ((current-line-string (save-restriction
                               (widen)
                               (save-excursion
                                 (buffer-substring-no-properties (line-beginning-position) (line-end-position))))))
    (when current-line-string
      (let ((url (magit-circleci--find-build current-line-string)))
        (message "browser build")
        (cond ((string-match-p "approve" current-line-string) (message "Cannot open approve url"))
              (t (browse-url url)))))))

(defun magit-circleci--approve-workflow ()
  "Approve workflow under cursor"
  (interactive)
  (let ((current-line-string (save-restriction
                               (widen)
                               (save-excursion
                                 (buffer-substring-no-properties (line-beginning-position) (line-end-position))))))
    (when (string-match-p "wait for" current-line-string)
      (magit-circleci--request "POST" (magit-circleci--find-build current-line-string))
      (magit-circleci-pull))))

;; Handle cache file
(defun magit-circleci--cache-file-location ()
  "Get the filename of the cache file for current repo."
  (format "%s.git/circleci" (magit-toplevel)))

(defun magit-circleci--cache-file-exists ()
  "Return t if the cache file exists."
  (file-exists-p (magit-circleci--cache-file-location)))

(defun magit-circleci--read-cache-file ()
  "Read the data that was cached into the `circleci` file in the .git folder."
  (car (read-from-string (with-temp-buffer
                           (insert-file-contents (magit-circleci--cache-file-location))
                           (buffer-string)))))

(defun magit-circleci--write-cache-file (data)
  "Write the cache da   ta to a `circleci` file in the .git folder.
DATA is the circleci data."
  (with-temp-buffer
    (prin1 data (current-buffer))
    (write-file (magit-circleci--cache-file-location))))

(defun magit-circleci--update-cache (reponame data)
  "Update the memory cache with data for reponame.
REPONAME is the name of the repo.
DATA is the circleci data."
  (delete (assoc (magit-circleci--current-branch) magit-circleci--cache) magit-circleci--cache)
  (push (cons (magit-circleci--current-branch) data) magit-circleci--cache)
  (magit-circleci--write-cache-file magit-circleci--cache))

;; Insert Circle item in Magit
(defun magit-circleci--format-section-heading (job-number status content)
  (cond ((equal job-number nil)
         (propertize (format "%s" content) 'face '(:foreground "#ff79c6")))
        ((equal status "success")
         (propertize (format "%s" content) 'face 'success))
        ((equal status "running")
         (propertize (format "%s" content) 'face 'warning))
        (t (propertize (format "%s" content) 'face 'error))))

(defun magit-circleci--insert-build (build pipeline-number workflow-id)
  "Insert current build.
BUILD is the build object."
  (let* ((status (cdr (assoc 'status build)))
         (subject (cdr (assoc 'name build)))
         (job-number (cdr (assoc 'job_number build)))
         (job-number-display (cond ((equal job-number nil) "")
                                   (t (format "%s - " job-number)))))
    (magit-section-hide
     (magit-insert-section (circleci)
       (magit-insert-heading
         (concat (magit-circleci--format-section-heading job-number status (format "%s" job-number-display))
                 (magit-circleci--format-section-heading job-number status (format "%s" subject))
                 (cond ((equal job-number nil)
                        (magit-circleci--format-section-heading job-number
                                                                status
                                                                (format " - %s" (if (equal status "success") "Approved" "Wait for approve"))))
                       (t ""))))))))

(defun magit-circleci--insert-workflow (builds)
  "Insert the builds as workflows.
BUILDS are the circleci builds."
  (let ((pipeline-number (cdr (assoc "pipeline_number" builds)))
        (workflow-name (cdr (assoc "workflow_name" builds)))
        (workflow-status (cdr (assoc "workflow_status" builds)))
        (workflow-id (cdr (assoc "workflow_id" builds))))
    (magit-insert-section (workflow)
      (magit-insert-heading (propertize (format "%s - %s" workflow-name workflow-status) 'face 'magit-section-secondary-heading))
      (seq-map #'(lambda (data)(magit-circleci--insert-build data pipeline-number workflow-id)) (cdr (assoc "items" builds))))))

;; Workflow
;; Integrate to Magit
(defun magit-circleci--section ()
  "Insert CircleCI section in magit status."
  (let* ((memcache (assoc (magit-circleci--current-branch) magit-circleci--cache))
         (data (cond (memcache (list memcache))
                     ((magit-circleci--cache-file-exists)
                      (magit-circleci--read-cache-file))))
         (builds (cdr (assoc (magit-circleci--current-branch) data))))
    (when builds
      (magit-insert-section (root)
        (magit-insert-heading (propertize "CircleCi" 'face 'magit-section-heading))
        (seq-map
         (lambda (item) (magit-circleci--insert-workflow item))
         builds)
        (insert "\n")))))

(transient-define-prefix circleci-transient ()
  "Dispatch a CircleCI Command"
  ["Fetch"
   ("f" "builds" magit-circleci-pull)])

(defvar magit-circleci-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap magit-browse-thing] #'magit-circleci-browse-build)
    (define-key map [remap magit-visit-thing] #'magit-circleci-browse-build)
    map))

(defvar magit-circleci-section-keybinding-map
  (define-key magit-mode-map "\"" #'circleci-transient)
  )


;; Autoload
(defun magit-circleci--activate ()
  "Add the circleci section and hook up the transient."
  (magit-add-section-hook 'magit-status-sections-hook #'magit-circleci--section
                          'magit-insert-staged-changes 'append)

  (transient-append-suffix 'magit-dispatch '(0 -1 -1)
    '("\"" "CircleCI" circleci-transient ?Z))

  (with-eval-after-load 'magit-mode
    (message "After load magit-mode")
    (define-key magit-mode-map (kbd "C-c C-a") #'magit-circleci--approve-workflow)
    (magit-circleci-pull)
    magit-circleci-section-keybinding-map))

(defun magit-circleci--deactivate ()
  "Remove the circleci section and the transient."
  (remove-hook 'magit-status-sections-hook #'magit-circleci--section)
  (transient-remove-suffix 'magit-dispatch "\""))

(define-minor-mode magit-circleci-mode
  "CircleCI integration for Magit"
  :group 'magit-circleci
  :global t
  (if (member 'magit-circleci--section magit-status-sections-hook)
      (magit-circleci--deactivate)
    (magit-circleci--activate)))

(provide 'magit-circleci)
