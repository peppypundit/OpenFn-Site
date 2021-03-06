'use strict'

OpenFn.Mappings.controller 'MappingViewCtrl',
  (mappingId,MappingViewModel,$q,$scope,$modal,$log,ConnectionProfiles,growl) ->

    self = this

    self.ui = {
      initializing: true
    }

    ConnectionProfiles.fetchDestinations().then (cp) =>
      self.destinationProfiles = cp.data

    ConnectionProfiles.fetchSources().then (cp) =>
      self.sourceProfiles = cp.data

    self.showNewProfileModal = (product) ->
      modalInstance = null

      # TODO: This should be replaced when Product(s) have a flag on them
      # representing if it's a source or destination (or both) product.

      if(/odk/i.test(product.name))
        templateUrl = '/templates/mappings/new_odk_profile_modal.html'
        connectionProfileType = 'source'
      else
        templateUrl = '/templates/mappings/new_sf_profile_modal.html'
        connectionProfileType = 'destination'

      modalInstance = $modal.open
        templateUrl: templateUrl
        controller: 'NewProfileModalController',
        size: 'md',
        resolve:
          product: -> product
          connectionProfileType: -> connectionProfileType

      modalInstance.result.then (profile) ->
        ConnectionProfiles.save(profile)
          .success (newConnectionProfile) ->
            if newConnectionProfile.type == 'source'
              self.sourceProfiles.connection_profiles.push newConnectionProfile
            else
              self.destinationProfiles.connection_profiles.push newConnectionProfile
            growl.success("The new prodct connection has been saved.", { ttl: 5000 })
          .error (error) ->
            $log.error(error);
            growl.error("We could not save the product connection. Please try again.", { ttl: 5000 })
      , ->
        $log.info('Modal dismissed at: ' + new Date())


    $q (resolve,reject) ->
      # Hand over mappingId to View model and bind callbacks.
      self.mapping = new MappingViewModel(mappingId, {

        # Just in case for now, props seem to update quickly.
        onUpdate: ->
          $scope.$apply()
          growl.success 'Mapping successfully updated.', ttl: 5000
        onChange: ->
          console.log "got change from viewmodel:", arguments
        # Open modal when we get an error
        onError: (mapping,e) ->
          $modal.open
            templateUrl: "/templates/errorModal.html"
            controller: "ErrorModalCtrl"
            size: "md"
            resolve:
              message: -> e

      })
      resolve(true)
    .then ->
      self.ui.initializing = false
    .catch (reason) ->
      console.error reason

    return this

.controller 'ErrorModalCtrl', ($modalInstance,$scope,message) ->

  $scope.message = message

  $scope.ok = ->
    $modalInstance.close()

.controller 'NewProfileModalController',
  ($modalInstance, $scope, product, connectionProfileType, CredentialsService, growl) ->
    console.log connectionProfileType
    $scope.profileObj = { type: connectionProfileType }
    $scope.credential = { type: product.credential_type }

    $scope.create = ->
      $scope.profileObj.product_id = product.id

      CredentialsService.create($scope.credential)
      .success (response) ->
        if response.valid
          $scope.profileObj.credential_id = response.credential.id
          $modalInstance.close $scope.profileObj
        else
          growl.error("Your credentials are invalid.");
      .error (err) ->
        console.log(err)
        growl.error("We could not verify your credentials. Please try again.");

    $scope.dismiss = ->
      $modalInstance.dismiss
