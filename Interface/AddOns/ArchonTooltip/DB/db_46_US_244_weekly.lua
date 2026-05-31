local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warrior-Fury','Druid-Feral','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-05-31',data={Aa='Aaminae:BAABLgAECn8oAAIBAAgJkxdiFgDUAQABAAgJkxdiFgDUAQAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgQJCQAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRqCLQCfAQADAAYJiRqCLQCfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAAALgADCgkJCQAAAA==.Aethlin:BAABLgAECn81AAMFAAkJ4BtMLAA4AgAFAAkJjRlMLAA4AgAGAAgJdhvWCQAYAgAAAA==.Aetreyu:BAAALgAECgYJBgAAAA==.Aeturnas:BAABLgAECn8tAAIHAAgJViEcCwDHAgAHAAgJViEcCwDHAgAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAABLgAECn8VAAMIAAcJOglbNAAjAQAIAAcJOglbNAAjAQAJAAYJ3AYPTAC6AAAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAECgIJBQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECggJEAAAAA==.Alros:BAABLgAECn8+AAIKAAkJGSJxBgAfAwAKAAkJGSJxBgAfAwAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='Aneas:BAAALgAECgUJBQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAABLgAECn8eAAIFAAgJ1hyrLAA3AgAFAAgJ1hyrLAA3AgAAAA==.Arkshade:BAABLgAECn8uAAILAAcJfRH1egBaAQALAAcJfRH1egBaAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJAwACAAAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAMAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgYJCwACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Asmo:BAAALgADCggJGAAAAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn9IAAINAAkJWBjuLAAaAgANAAkJWBjuLAAaAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAIOAAYJ+A16UwA4AQAOAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIPAAcJBxbEJwBjAQAPAAcJBxbEJwBjAQAAAA==.',
Aw='Awasjr:BAABLgAECn8kAAIKAAkJhx8GFACdAgAKAAkJhx8GFACdAgAAAA==.Awassy:BAAALgAECgEJAQAAAA==.',
Ay='Ayano:BAABLgAECn8WAAIQAAgJYh68QwD7AQAQAAgJYh68QwD7AQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgADCgIJAgAAAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDQABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAABLgAECn8sAAMDAAgJcBdkIACwAQADAAcJixlkIACwAQAPAAcJ2geBQgANAQABLgAFFAQJCgARAHYHAA==.Bearshock:BAACLgAFFH8KAAMRAAQJdgfTJgDjAAARAAQJdgfTJgDjAAAOAAEJTABreQAdAAAuAAQKfxoAAhEACAlOGo4UAC8CABEACAlOGo4UAC8CAAAA.Beasty:BAABLgAECn8lAAMSAAgJHhCTDwBJAQASAAgJHhCTDwBJAQATAAYJhwSOOQDaAAAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn8yAAIGAAkJzCTrAABJAwAGAAkJzCTrAABJAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJMgAGAMwkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJMgAGAMwkAA==.Beethicc:BAAALgAECgEJBAABLgAECgkJMgAGAMwkAA==.Beeuwu:BAAALgAECgIJAwABLgAECgkJMgAGAMwkAA==.Beliara:BAAALgAECggJDAAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn8uAAIQAAkJtBoYLgBLAgAQAAkJtBoYLgBLAgAAAA==.Bishopwr:BAABLgAECn8nAAMUAAkJ8BaoCgAnAgAUAAkJ8BaoCgAnAgAVAAYJCwpGLgC1AAAAAA==.Bittertøfu:BAABLgAECn8eAAIRAAcJfQadTwDeAAARAAcJfQadTwDeAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCQAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8UAAIQAAcJdg01yABYAQAQAAcJdg01yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJNQAWADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJBwALAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMQAAkJHiMULgC5AgAQAAkJHiMULgC5AgAXAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8HAAIXAAMJURKqAQDfAAAXAAMJURKqAQDfAAAuAAQKfxsAAhcACAmCHB4EABICABcACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIYAAgJ2wVZPwD3AAAYAAgJ2wVZPwD3AAAAAA==.Briara:BAAALgAECgYJCQAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJBAAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAABLgAECn83AAMLAAkJHiOwCQAUAwALAAkJHiOwCQAUAwAZAAQJnRQfGADlAAAAAA==.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgYJCAABLgAFFAMJBQAaAFkdAA==.',
Bu='Bullshott:BAABLgAECn8jAAIKAAkJrx2wFwCDAgAKAAkJrx2wFwCDAgAAAA==.Bum:BAABLgAECn8mAAMYAAkJsh/4BABRAwAYAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEAAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8VAAMLAAgJQA2NmAAlAQALAAcJsQqNmAAlAQAbAAYJdA1+LQDZAAAAAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8wAAIFAAkJMghRgQBSAQAFAAkJMghRgQBSAQAAAA==.Carrots:BAABLgAECn8lAAIKAAgJFBQJRQC9AQAKAAgJFBQJRQC9AQAAAA==.Cartman:BAAALgAFFAEJAQABLgAFFAQJGgAaAI4bAA==.Cashmachine:BAABLgAECn8tAAIKAAkJAx+EFQCTAgAKAAkJAx+EFQCTAgAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn8pAAIGAAcJQhDAHQAPAQAGAAcJQhDAHQAPAQAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMNAAkJdBhqLgBTAgANAAkJdBhqLgBTAgAcAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8MAAQKAAQJ3B7/JABOAQAKAAQJuB3/JABOAQASAAEJISI3IwBlAAATAAEJzA/rLABKAAAuAAQKfxoABBIACAkNIcIYAGYCABIACAmlH8IYAGYCAAoABQlPHUVSAJYBABMAAwkrGB1HAIcAAAAA.Cheesecake:BAABLgAECn8nAAIcAAgJaxG3CwBpAQAcAAgJaxG3CwBpAQAAAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn8hAAIdAAcJEg1NPABBAQAdAAcJEg1NPABBAQAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAeAAUJYh2qFABVAQAAAA==.Chuggz:BAABLgAECn8zAAIaAAkJURm6DQBKAgAaAAkJURm6DQBKAgAAAA==.Chéfboyrlee:BAACLgAFFH8YAAIJAAgJ4BZjAwAoAgAJAAgJ4BZjAwAoAgAuAAQKfzYAAgkACQn6IqoDABADAAkACQn6IqoDABADAAAA.',
Ci='Cizmac:BAAALgAECgQJCQAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJCgAAAA==.Cownado:BAABLgAECn8vAAIaAAcJTRFRLABGAQAaAAcJTRFRLABGAQABLgAECggJFQALAEANAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIRAAkJmB4QDgB2AgARAAkJmB4QDgB2AgAAAA==.Cyfelen:BAABLgAECn8UAAQcAAkJiB8cAQDeAgAcAAkJiB8cAQDeAgAfAAMJ4hW7IwB5AAANAAEJchC6KAE1AAAAAA==.Cynleel:BAAALgAECggJEAAAAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMaAAkJdx0FCgCDAgAaAAkJbh0FCgCDAgAPAAEJchK2fAAzAAAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgMJAwAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAAALgAFFAIJAwAAAA==.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAAALgAECgYJBgABLgAFFAQJGgAaAI4bAA==.Delrager:BAACLgAFFH8GAAIBAAIJ7xt5KACsAAABAAIJ7xt5KACsAAAuAAQKfyEAAgEABwlnI7UMAEQCAAEABwlnI7UMAEQCAAAA.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.',
Di='Dibbydab:BAABLgAECn8gAAIOAAkJShJgNADHAQAOAAkJShJgNADHAQAAAA==.',
Dj='Django:BAABLgAECn82AAMYAAkJsyIZBQD7AgAYAAkJsyIZBQD7AgAEAAIJkAb1uABBAAAAAA==.Djatalon:BAABLgAECn8WAAMgAAUJuAvNIADZAAAgAAUJuAvNIADZAAAhAAMJrAWtGQBvAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgADCggJEgAAAA==.Djin:BAAALgAECgMJBAABLgAFFAMJBQAaAFkdAA==.Djinni:BAACLgAFFH8FAAIaAAMJWR3bIwAFAQAaAAMJWR3bIwAFAQAuAAQKfy4AAw8ACQllHqoMAGcCAA8ACQkSG6oMAGcCABoACAmPH/kOADsCAAAA.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8WAAMZAAYJfBjBBQDVAQAZAAYJfBjBBQDVAQALAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQgAAcJNxmKDgDUAQAgAAcJNxmKDgDUAQAiAAQJuwx4WgCmAAAhAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAAALgAECgkJEAABLgAECgkJNAAjAKIWAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJNAAjAKIWAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8dAAMQAAcJuBQ5iABNAQAQAAcJuBQ5iABNAQAXAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECgkJNAAdABgjAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJCAAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn80AAMQAAkJnhPRPAARAgAQAAkJnhPRPAARAgAXAAQJTQoTEADBAAAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAAALgAECgIJAgAAAA==.Elessedil:BAAALgAECgcJDQAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgQJCQAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSDuBwArAwAEAAkJpSDuBwArAwAeAAEJqSDqNgBcAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8WAAIKAAYJuh4VTwCfAQAKAAYJuh4VTwCfAQABLgAECggJIAAKACwgAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgcJDgAAAA==.Emritelan:BAAALgADCgcJBwAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8WAAIFAAUJjBtcMQAzAQAFAAUJjBtcMQAzAQAuAAQKfzEAAgUACQmaH/EeAHcCAAUACQmaH/EeAHcCAAAA.',
Ep='Epedemik:BAAALgAECgIJAgAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAbAI8JAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAAALgAFFAIJAwAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAMAI8fAA==.Favel:BAABLgAECn8qAAMMAAkJjx9OAQAcAwAMAAgJ4iFOAQAcAwAjAAkJRwudWABmAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn86AAIKAAkJShbBJgAwAgAKAAkJShbBJgAwAgAAAA==.Febz:BAABLgAECn8eAAIQAAgJbBsqMACyAgAQAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8ZAAIjAAgJEh1KKAAWAgAjAAgJEh1KKAAWAgAAAA==.Felfüry:BAABLgAECn89AAQkAAkJuhR8EAADAgAkAAkJuhR8EAADAgAMAAgJtga2FQDhAAAjAAEJJAN9IgEVAAAAAA==.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgQJBgACAAAAAA==.Finella:BAAALgAECgkJDQAAAA==.Finneas:BAAALgAECgEJAQABLgAECggJHgAFANYcAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAQAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgkJDQACAAAAAA==.',
Fj='Fjeighty:BAABLgAECn8gAAMkAAcJKg+IJQAsAQAkAAcJKg+IJQAsAQAjAAEJ6QOYGwEcAAAAAA==.',
Fo='Fogassann:BAAALgAECgcJCgAAAA==.Fogdemon:BAAALgAECgIJBAABLgAFFAUJFgAfAHMUAA==.Foggpy:BAACLgAFFH8WAAMfAAUJcxSkAwBBAQAfAAUJcxSkAwBBAQANAAQJnwNqYwDfAAAuAAQKfycABB8ACAmeInUEADYCAB8ABwkkJXUEADYCAA0ABgkNG8FXAMABABwABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostybear:BAABLgAECn9IAAIQAAkJARkLJwBqAgAQAAkJARkLJwBqAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn8xAAMbAAkJPAltIQAvAQAbAAkJPAltIQAvAQAZAAEJ8QE8OQAaAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgADCgEJAQAAAA==.Galaythien:BAAALgAECgQJBwAAAA==.Gang:BAAALgAECgUJBQABLgAFFAMJDQABAMUOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAjAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMbAAkJdB1bBgCrAgAbAAkJdB1bBgCrAgAZAAEJ5Q5GMgAvAAABLgAECgkJNAAaADckAA==.Geret:BAABLgAECn8iAAIFAAgJdxORZQCMAQAFAAgJdxORZQCMAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Gleesh:BAAALgAECgEJAQABLgAECggJFgAQAGIeAA==.Glitchy:BAABLgAECn9DAAMYAAkJmR6lCAC3AgAYAAkJIR6lCAC3AgAlAAYJGhagFQCHAQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn9DAAMGAAkJCSPhAQASAwAGAAkJCSPhAQASAwAFAAYJBxCegwBOAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAWAD4fAA==.Goldfarmr:BAABLgAECn8rAAIWAAkJPh+7CgCoAgAWAAkJPh+7CgCoAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAWAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAWAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAWAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJHAAGAPwhAA==.Greeley:BAABLgAECn81AAISAAkJEyS/AABDAwASAAkJEyS/AABDAwAAAA==.Gregdapro:BAABLgAECn9NAAIbAAkJuSWxAABnAwAbAAkJuSWxAABnAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRZQJADQAQAHAAkJlRZQJADQAQABLgAECgkJTQAbALklAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJDwAiAGAQAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAcJIwAdACsdAA==.Gunnyal:BAABLgAECn8mAAMUAAcJRBGyHwBKAQAUAAcJ5xCyHwBKAQAdAAQJsAnlZACtAAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIRAAkJUyNFBAAQAwARAAkJUyNFBAAQAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8jAAMdAAcJKx08AwARAgAdAAcJKx08AwARAgAUAAEJNAEQDgA8AAAuAAQKfzwAAx0ACQktJcIBAFcDAB0ACQktJcIBAFcDABQAAwldHNk0ANoAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgADCgkJCQAAAA==.Harkin:BAABLgAECn82AAIFAAkJDxI8VAC2AQAFAAkJDxI8VAC2AQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgQJCQAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIRAAcJXQu6RQADAQARAAcJXQu6RQADAQAAAA==.Hermioné:BAAALgADCgUJBQAAAA==.Hevy:BAABLgAECn80AAIjAAkJoha1JwAZAgAjAAkJoha1JwAZAgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAMJBQAaAFkdAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9AAAIFAAkJxxhaJwBOAgAFAAkJxxhaJwBOAgAAAA==.Hottice:BAAALgAECgEJAQAAAA==.Howlinnbrews:BAABLgAFFH8HAAMPAAMJBiMWFgACAQAPAAMJ2BsWFgACAQAaAAEJ6CW0RwBnAAAAAA==.Howlinplague:BAAALgAECgYJCQAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIVAAkJAR3vBgCEAgAVAAkJAR3vBgCEAgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIjAAMJRBoYUADdAAAjAAMJRBoYUADdAAAuAAQKfycAAiMACAkuIrAVANQCACMACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBj6JQANAgAEAAgJjBj6JQANAgAeAAIJ1hK6PQBIAAAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIPAAcJVBaSMQArAQAPAAcJVBaSMQArAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Io:BAAALgAFFAMJAwAAAA==.Iobo:BAABLgAECn8oAAITAAcJpRLBHwCRAQATAAcJpRLBHwCRAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8vAAIFAAkJewxuZwCIAQAFAAkJewxuZwCIAQAAAA==.',
Is='Isaarek:BAABLgAECn8bAAIiAAkJkxUVEwAvAgAiAAkJkxUVEwAvAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDgAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAcJHQALAIUbAA==.Jasmini:BAAALgAECgEJAQAAAA==.Jastia:BAAALgAECgYJEgAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8sAAMNAAkJAhyrGgB4AgANAAkJAhyrGgB4AgAcAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8sAAIFAAkJcgvNagCAAQAFAAkJcgvNagCAAQAAAA==.',
Jo='Joecephus:BAABLgAECn8iAAIHAAcJZyKSDQClAgAHAAcJZyKSDQClAgAAAA==.Joehex:BAABLgAECn85AAIVAAkJgyFpAwDwAgAVAAkJgyFpAwDwAgAAAA==.Joeschmonk:BAAALgAECgQJBAAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJBwABLgAECgkJHwAKAMUVAA==.Judgematt:BAABLgAECn8WAAIHAAkJBRS5FwA1AgAHAAkJBRS5FwA1AgAAAA==.Justin:BAABLgAECn8fAAIUAAkJvhU1DAAOAgAUAAkJvhU1DAAOAgAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAISAAgJ1AzQEQAqAQASAAgJ1AzQEQAqAQAAAA==.Kaleesh:BAACLgAFFH8QAAImAAYJdyX8AAADAgAmAAYJdyX8AAADAgAuAAQKfyQAAiYACAnWJEcBAGgDACYACAnWJEcBAGgDAAAA.Kallux:BAABLgAECn89AAIbAAkJRx7PBgCgAgAbAAkJRx7PBgCgAgAAAA==.Kananga:BAABLgAECn8bAAIWAAcJlxj9HwCwAQAWAAcJlxj9HwCwAQAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBQAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECgQJBAAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgQJCAAAAA==.',
Ki='Kieleron:BAABLgAECn8cAAIIAAgJWhBrHADLAQAIAAgJWhBrHADLAQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJDgAAAA==.Kiermaxim:BAABLgAECn8mAAIRAAgJNBwcGwA6AgARAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJNgAFAAwSAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBBHJwDEAQADAAkJxBBHJwDEAQAAAA==.Kiraneth:BAABLgAECn8gAAIPAAgJMBDOJwBjAQAPAAgJMBDOJwBjAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECggJEwAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgQJBAAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAECgcJCgAAAA==.Largcok:BAAALgAECgIJAgAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAUJAQAAAA==.Lefty:BAAALgADCgcJBwABLgAECgkJOwATAAoUAA==.Leyn:BAAALgAECgQJBAAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQAJADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn85AAIdAAkJ0iRIAgBFAwAdAAkJ0iRIAgBFAwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8KAAIOAAMJ0wuGSACxAAAOAAMJ0wuGSACxAAAuAAQKfykAAg4ACAmGG5ItAOkBAA4ACAmGG5ItAOkBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn82AAIFAAkJDBInVAC2AQAFAAkJDBInVAC2AQAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgEJAgABLgAECgcJJAAQAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8WAAIKAAcJ3SJ9GAB2AgAKAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyais:BAAALgADCgIJAgAAAA==.Lyara:BAACLgAFFH8ZAAMOAAYJ5yMkBQBAAgAOAAYJ5yMkBQBAAgARAAQJRxiCGQApAQAuAAQKfxwAAw4ACQnAIFAJAOICAA4ACAkVIFAJAOICABEABglnG205ADgBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lythos:BAACLgAFFH8HAAIbAAMJjwmJJQCZAAAbAAMJjwmJJQCZAAAuAAQKfxkAAhsACAmPE2obAHMBABsACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAYJGQAOAOcjAA==.Lyuu:BAABLgAFFH8GAAIQAAMJdxZRcQDfAAAQAAMJdxZRcQDfAAABLgAFFAYJGQAOAOcjAA==.',
['Lø']='Lørdøfßud:BAABLgAECn80AAMdAAkJGCOYBQD3AgAdAAkJuCGYBQD3AgAUAAcJEiPXCQA2AgAAAA==.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAjAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgADCgYJBgABLgAECgkJHwAKAMUVAA==.Makinnor:BAAALgADCgEJAQAAAA==.Malifae:BAABLgAECn8bAAIYAAcJYSGbEwB3AgAYAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAYAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAABLgAECn82AAInAAkJahpMAwBuAgAnAAkJahpMAwBuAgAAAA==.Mastamojo:BAABLgAECn84AAIHAAkJiQjbNABqAQAHAAkJiQjbNABqAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECgcJDwAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAQAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAABLgAECn8aAAMcAAgJBhcwDgBCAQAcAAcJqRMwDgBCAQAfAAQJnRbwEgAcAQAAAA==.Melendaren:BAAALgAECgMJBQAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgIJAgAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIWAAgJngonNAAgAQAWAAgJngonNAAgAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8kAAMYAAcJThH6LwBFAQAYAAcJThH6LwBFAQAEAAYJ1gssZgDyAAABLgAECggJLQAWAFYTAA==.Metamonster:BAABLgAECn8jAAMLAAgJRQ2gjgA2AQALAAgJVAegjgA2AQAbAAYJ4w8QMwC3AAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgUJCgAAAA==.Mirko:BAABLgAECn8dAAIjAAcJhguvggAAAQAjAAcJhguvggAAAQAAAA==.Mistiah:BAABLgAFFH8HAAILAAMJQyDXXwAfAQALAAMJQyDXXwAfAQAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9AAAIXAAkJZBjTAQBbAgAXAAkJZBjTAQBbAgAAAA==.Mokokniki:BAAALgADCggJCQAAAA==.Moneie:BAAALgAECgUJCgAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgAECgEJAQAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJBgARAGsPAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgADCgYJBgAAAA==.Mourningstar:BAACLgAFFH8WAAMLAAUJiSU7JQCaAQALAAQJiSU7JQCaAQAbAAEJAAA1UAAAAAAuAAQKfyQAAwsACQkeJL0UALoCAAsACQkeJL0UALoCABsAAgm1EZdAAHQAAAEuAAUUBwkdAAsAhRsA.Mozaic:BAABLgAECn8/AAIVAAkJ1hgdCgA9AgAVAAkJ1hgdCgA9AgAAAA==.',
Mu='Mugrüíth:BAAALgAECgQJCAAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgMJAwABLgAECgkJNAAdABgjAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8gAAIkAAgJhRb0EwDTAQAkAAgJhRb0EwDTAQAAAA==.Mystra:BAAALgAECgYJCwAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgQJCQAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgQJCQACAAAAAA==.Nalthis:BAAALgAECgQJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn8kAAIQAAcJHRK8gABdAQAQAAcJHRK8gABdAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8ZAAIjAAgJvQmwewAPAQAjAAgJvQmwewAPAQAAAA==.Niem:BAABLgAECn8dAAIlAAkJhSUAAQBUAwAlAAkJhSUAAQBUAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.',
No='Nocturnum:BAABLgAECn8zAAIjAAgJ6BlvMADwAQAjAAgJ6BlvMADwAQAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIfAAUJQRdPAABcAQAfAAUJQRdPAABcAQAuAAQKfxwAAh8ACAktHi8BAPECAB8ACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgAECgEJAQAAAA==.Odium:BAAALgADCgMJAwABLgAFFAQJDAAKANweAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAcJGAASAIwiAA==.',
Ol='Oldmage:BAAALgADCgUJBQAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn9DAAIDAAkJKBg+FABbAgADAAkJKBg+FABbAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9IAAMFAAkJViJwDwATAwAFAAkJViJwDwATAwAGAAkJyRW6CQAaAgAAAA==.Orionn:BAACLgAFFH8TAAIKAAQJRSC0CQAUAQAKAAQJRSC0CQAUAQAuAAQKf0MAAgoACQm2JZkDAEwDAAoACQm2JZkDAEwDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8ZAAIKAAgJiwzNWgB+AQAKAAgJiwzNWgB+AQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIPAAgJVxbtHQCpAQAPAAgJVxbtHQCpAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgUJCgAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgADCgcJBwAAAA==.Prayr:BAAALgADCgMJBAAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAINAAkJ3BXfLwAOAgANAAkJ3BXfLwAOAgAAAA==.Raelone:BAABLgAECn8dAAQcAAkJGBHpHwCYAAANAAUJYg1WngD5AAAcAAYJZBLpHwCYAAAfAAEJ5RPXLwBIAAAAAA==.Rageofmommy:BAAALgAECgMJAwAAAA==.Raidoe:BAABLgAECn9FAAMDAAkJmhvPDQCiAgADAAkJmhvPDQCiAgAPAAMJOQsFagBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8zAAIKAAkJoxhpKAAoAgAKAAkJoxhpKAAoAgAAAA==.Rant:BAAALgAECgUJCgAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgMJAwABLgAECgkJQAAXAGQYAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAEJAQAAAA==.Redward:BAABLgAECn8vAAIFAAkJShI7RgDcAQAFAAkJShI7RgDcAQAAAA==.Relion:BAAALgAECgQJBAABLgAECgkJOQAFACMQAA==.',
Rh='Rheavin:BAAALgADCgUJBQAAAA==.Rhell:BAACLgAFFH8OAAIHAAQJqhMyIwDzAAAHAAQJqhMyIwDzAAAuAAQKfzUAAgcACQnCH2QIAPICAAcACQnCH2QIAPICAAAA.',
Ri='Rinche:BAABLgAECn9CAAMRAAkJNxaLGAAIAgARAAkJNxaLGAAIAgAOAAgJ0goKZQAQAQAAAA==.Rintche:BAAALgAECgMJAwAAAA==.',
Ro='Rolland:BAABLgAECn8cAAISAAgJTB9/BQA4AgASAAgJTB9/BQA4AgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8aAAMNAAkJ9AjuWgCDAQANAAkJ9AjuWgCDAQAcAAQJ1wTCJABzAAAAAA==.',
Ru='Rudo:BAABLgAECn8fAAMKAAkJxRVZIgA3AgAKAAkJxRVZIgA3AgATAAEJrgJDYgAoAAAAAA==.Rumproblem:BAABLgAECn8lAAMIAAkJqhANFgAKAgAIAAkJqhANFgAKAgAJAAcJuAv+MwAoAQAAAA==.Runnamuuk:BAABLgAECn82AAIjAAkJGBRzMgDnAQAjAAkJGBRzMgDnAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgADCgkJCQAAAA==.Ryeger:BAABLgAECn82AAMeAAkJYxyoBACZAgAeAAkJYxyoBACZAgAYAAMJpgswXQCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8rAAIlAAkJsxN4FwB0AQAlAAkJsxN4FwB0AQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn85AAMFAAkJIxB0TgDFAQAFAAkJIxB0TgDFAQAHAAkJYwPePwAwAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJQAAXAGQYAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgADCgMJBAAAAA==.Sansami:BAABLgAECn80AAIaAAgJpRtrFgDnAQAaAAgJpRtrFgDnAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8WAAMYAAcJ+QYcRADhAAAYAAcJ+QYcRADhAAAEAAUJDQPznwBiAAAAAA==.',
Sc='Scalebagz:BAABLgAECn8gAAMgAAkJSB6SBQCpAgAgAAkJSB6SBQCpAgAiAAgJvRz7HQDQAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCAAAAA==.Serabeara:BAAALgAECgEJAQAAAA==.Setresh:BAABLgAECn9IAAITAAkJwhWrEAAcAgATAAkJwhWrEAAcAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn84AAIVAAgJLAvKHgAlAQAVAAgJLAvKHgAlAQAAAA==.Shaedelana:BAABLgAECn8XAAQIAAYJrBrNOAALAQAIAAUJShPNOAALAQAWAAQJ5xvbTwD4AAAJAAQJTQ/NUQCjAAAAAA==.Shamrox:BAAALgAECggJDwAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAMAI8fAA==.Shivyn:BAABLgAECn86AAMOAAkJURRRHgBDAgAOAAkJURRRHgBDAgARAAEJFwW5jQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAcJGAASAIwiAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8IAAILAAIJBA+uuwCNAAALAAIJBA+uuwCNAAAuAAQKfy4AAwsACQmlGZk/APMBAAsACQmlGZk/APMBABsABQmtD1UuAMwAAAAA.Sickkid:BAABLgAECn85AAIdAAgJLCADDACWAgAdAAgJLCADDACWAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8eAAIdAAkJihMmGwADAgAdAAkJihMmGwADAgAAAA==.Silvershine:BAABLgAECn8UAAMEAAYJyw4lgADaAAAEAAUJYgslgADaAAAeAAQJuAZfLwCBAAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgQJBgAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJBwALAEMgAA==.Snuggles:BAABLgAECn8jAAIkAAgJjxoSEAAJAgAkAAgJjxoSEAAJAgABLgAFFAUJGQATADAZAA==.',
So='Solidgen:BAAALgAECgEJAgAAAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMVAAgJNRbdFACOAQAVAAgJNRbdFACOAQAUAAMJUgOpNABeAAAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8KAAIlAAUJ9BmhCAA4AQAlAAUJ9BmhCAA4AQABLgAFFAYJHAAGAPwhAA==.',
St='Staretra:BAABLgAECn88AAMJAAkJjBDNGwDMAQAJAAkJjBDNGwDMAQAWAAMJjgNyVwBjAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8xAAIWAAkJER5MDACMAgAWAAkJER5MDACMAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJCQAAAA==.',
Ta='Taadra:BAABLgAECn9EAAIOAAkJUx9YCQAIAwAOAAkJUx9YCQAIAwAAAA==.Talerah:BAAALgAECgMJBQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8RAAIEAAQJfBsuHABbAQAEAAQJfBsuHABbAQAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACUAAgkPE/9CAHMAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAfAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQANANwVAA==.Tanjent:BAABLgAECn8YAAIKAAYJxwo4mwDxAAAKAAYJxwo4mwDxAAAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn8pAAITAAcJWhbNHgCZAQATAAcJWhbNHgCZAQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECggJJAAFADAdAA==.Tatsumå:BAAALgAECgcJEgABLgAECggJJAAFADAdAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAKAN0iAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thorincan:BAAALgAECgkJBwAAAA==.Thorrs:BAAALgAECgIJBgAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgEJAQAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgQJBgACAAAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn9DAAIaAAkJKyEIBAD9AgAaAAkJKyEIBAD9AgAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAUJAQACAAAAAA==.',
To='Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAMJBQAaAFkdAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8fAAIYAAkJLhqWGwAmAgAYAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAKAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQQAAgJ+iPjMQA7AgAQAAgJXCHjMQA7AgAXAAMJPCQCBwApAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRgTIAA1AgAEAAkJsRgTIAA1AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgQJCgAAAA==.Valle:BAAALgAECgYJCwAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJGgAaAI4bAA==.Variable:BAAALgAECgcJBwAAAA==.Vashdin:BAABLgAECn8cAAIFAAcJKBk+bAB9AQAFAAcJKBk+bAB9AQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8oAAIEAAkJDBrDFACRAgAEAAkJDBrDFACRAgAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8GAAIRAAMJaw90LADDAAARAAMJaw90LADDAAAAAA==.Vett:BAAALgADCgMJAwABLgAECgQJCgACAAAAAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgQJBAAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAKAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8QAAMDAAMJtRL8LQC8AAADAAMJtRL8LQC8AAAPAAIJlxmRJgCUAAAuAAQKfx4AAw8ACQmQHRcQAH8CAA8ACAlXHRcQAH8CAAMABQnvH+dLAAwBAAAA.Vivila:BAAALgAECgEJAgABLgAECgkJNAAjAKIWAA==.Vivillian:BAABLgAFFH8HAAIIAAMJjg8eKgDIAAAIAAMJjg8eKgDIAAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhiOAQBwAgAoAAkJqhiOAQBwAgAXAAEJuAV9IAAtAAAQAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQgAAgJKhn4EwAGAgAgAAgJKhn4EwAGAgAhAAQJxRjIEwC9AAAiAAEJygOkjAAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn8pAAMOAAcJsBkQMQDXAQAOAAcJsBkQMQDXAQARAAcJ5w+JPwAcAQAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn8nAAQMAAgJJByRBgAQAgAMAAgJJByRBgAQAgAkAAUJYAizQgDtAAAjAAEJdAGj9QAZAAAAAA==.',
['Ví']='Víx:BAAALgADCgIJAgAAAA==.',
['Vî']='Vîper:BAAALgAECgUJBQAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMUAAgJeQwhKgAPAQAdAAgJIwreOQBMAQAUAAgJhQkhKgAPAQAAAA==.Waycaps:BAAALgAFFAEJAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8HAAIfAAMJGCSdAwBCAQAfAAMJGCSdAwBCAQAuAAQKfy0AAh8ACQk/JJsAAB8DAB8ACQk/JJsAAB8DAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJBgAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgYJCQAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgQJBgACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBwAAAA==.',
Ya='Yacob:BAABLgAECn81AAIWAAkJOx2KCADRAgAWAAkJOx2KCADRAgAAAA==.',
Ye='Yenneferr:BAAALgADCgUJBQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx89CgAIAwAEAAkJEx89CgAIAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8LAAIbAAUJtAzdHADbAAAbAAUJtAzdHADbAAAuAAQKfyEAAhsACAk4GF8RAN4BABsACAk4GF8RAN4BAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAAALgAFFAQJBAABLgAECgkJDQACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBgAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zaeden:BAABLgAECn8cAAIDAAcJmx6fFgANAgADAAcJmx6fFgANAgABLgAECggJFgALACsgAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn8wAAIjAAkJVxW+NADeAQAjAAkJVxW+NADeAQAAAA==.Zaha:BAABLgAECn8eAAIQAAYJ2iKdXAAkAgAQAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zem:BAABLgAECn8qAAIdAAgJux+GDwBsAgAdAAgJux+GDwBsAgAAAA==.Zeroultra:BAABLgAECn8wAAIdAAgJBx3TEgBLAgAdAAgJBx3TEgBLAgAAAA==.Zeräse:BAAALgAECggJDwABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgADCgkJCQAAAA==.Zeusmos:BAABLgAECn8sAAIPAAkJOyZqAACJAwAPAAkJOyZqAACJAwAAAA==.',
Zi='Zithenex:BAABLgAECn8pAAIhAAcJURHrCgBYAQAhAAcJURHrCgBYAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJAwAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAAALgAECgYJEQAAAA==.',
['Ér']='Éragon:BAAALgAECgYJEwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
