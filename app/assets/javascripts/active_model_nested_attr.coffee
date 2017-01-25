$(document).on 'turbolinks:load', ->
  if $('.duplicatable_nested_form').length

    formsOnPage = $('.duplicatable_nested_form').length

    $('body').on 'click','.destroy_nested_form', (e) ->
      e.preventDefault()
      if $('.duplicatable_nested_form').length > 1
        $(this).closest('.duplicatable_nested_form').slideUp().remove()

    $('body').on 'click','.mark_nested_form_as_destroyed', (e) ->
      e.preventDefault()
      form = $(this).closest('.duplicatable_nested_form')
      form.find('input[id*="_destroy"]').val('true')
      form.slideUp().hide()

    $('.insert_nested_form').click (e) ->
      e.preventDefault()
      lastNestedForm = $('.duplicatable_nested_form').last()
      newNestedForm = $(lastNestedForm).clone()
      newNestedForm.show()
      formsOnPage += 1

      $(newNestedForm).find('label').each ->
        oldLabel = $(this).attr 'for'
        if oldLabel?
          newLabel = oldLabel.replace(new RegExp(/_[0-9]+_/), "_#{formsOnPage - 1}_")
          $(this).attr 'for', newLabel

      $(newNestedForm).find('select, input').each ->
        if $(this).is(':checkbox')
          $(this).prop('checked', false)
        else
          $(this).val('')
        oldId = $(this).attr 'id'
        if oldId?
          newId = oldId.replace(new RegExp(/_[0-9]+_/), "_#{formsOnPage - 1}_")
          $(this).attr 'id', newId

        oldName = $(this).attr 'name'
        newName = oldName.replace(new RegExp(/\[[0-9]+]/), "[#{formsOnPage - 1}]")
        $(this).attr 'name', newName

      $(newNestedForm).insertAfter(lastNestedForm)
