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

local lookup = {'Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','Mage-Arcane','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Paladin-Retribution','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Shaman-Elemental','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation','Shaman-Enhancement','Warlock-Demonology','Druid-Guardian','Monk-Brewmaster','Warlock-Affliction','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aakai:BAABNQAECn9NAAQBAAoKbxwnHwCEAgABAAoKNhsnHwCEAgACAAgKoBldBgBsAgADAAIKEQpYQwB5AAAAAA==.Aarmorr:BAABNQAECn9EAAIEAAkKzQkvbQBVAQAEAAkKzQkvbQBVAQAAAA==.',
Ac='Acinianis:BAAANQAECgEIAgAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgcICwAAAA==.Adsdad:BAAANQAECgQIBQAAAA==.',
Ae='Aedelas:BAAANQADCggIFQAAAA==.',
Ai='Aimeeiove:BAAANQAECgQIAwAAAA==.Airoldeel:BAAANQADCgcICAAAAA==.',
Ak='Akarag:BAAANQADCgcICgAAAA==.',
Al='Alcarza:BAAANQAECgEIAQAAAA==.Alchon:BAABNQAECn8kAAIFAAgK0xp7UwB2AgAFAAgK0xp7UwB2AgAAAA==.Alicalsastre:BAAANQAECggIEwAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAABNQAECn81AAMGAAgKiBJxJwCXAQAGAAgKiBJxJwCXAQAHAAUKzgS0hAC/AAAAAA==.Alunathsong:BAAANQAECgYIBwAAAA==.Alvagíngras:BAAANQAECgYICAAAAA==.',
Am='Amaith:BAAANQAECgQJDAAAAA==.Amantillado:BAAANQAECgIIBAABNQAECgYIDwAIAAAAAA==.Amata:BAAANQAECgQIBgAAAA==.Amblance:BAAANQAECggIDQAAAA==.Amelianne:BAAANQAECgQICQAAAA==.Amerria:BAAANQABCgMIAwAAAA==.Ammastary:BAAANQAECgQIBwAAAA==.Ammonfrey:BAAANQADCgUIBQAAAA==.',
An='Andrea:BAABNQAECn8yAAIJAAkKAxNYEQCRAQAJAAkKAxNYEQCRAQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAABNQAECn8iAAMKAAkKMRG1cgBrAQAKAAkKMRG1cgBrAQALAAQKUQdEVgCzAAAAAA==.',
Aq='Aqules:BAAANQADCggICwAAAA==.',
Ar='Arcapeligo:BAAANQAECgEIAgAAAA==.Archonsfury:BAAANQAECggIEwAAAA==.Ardagg:BAAANQAECgEIAgAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAABNQAECn8eAAIMAAoK7Be7bwBEAgAMAAoK7Be7bwBEAgAAAA==.',
As='Ashentris:BAABNQAECn8YAAINAAYK/ATu1QDtAAANAAYK/ATu1QDtAAAAAA==.Asnew:BAABNQAECn8zAAIOAAoKQBJkNgBeAQAOAAoKQBJkNgBeAQAAAA==.Asura:BAABNQAECn8iAAMPAAoKMBEEUQDPAQAPAAgKNhMEUQDPAQAQAAUKOglrcQDFAAAAAA==.',
At='Athelstan:BAABNQAECn8XAAILAAgKlgpdQAAsAQALAAgKlgpdQAAsAQAAAA==.Atonement:BAAANQADCgIIAgABNQAECgoKPQARALoeAA==.',
Au='Aumaril:BAAANQAECggIEQAAAA==.Auralynn:BAAANQAECgcIEgAAAA==.Auroriana:BAAANQAECgEIAQAAAA==.',
Av='Averus:BAABNQAECn9FAAIHAAkKFQt1MgBfAQAHAAkKFQt1MgBfAQAAAA==.',
Az='Azariel:BAABNQAECn8mAAMSAAoKqRB2mgDuAQASAAoKqRB2mgDuAQARAAEKAAB7dQAnAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAABNQAECn9EAAIRAAkKeBwHEQAEAgARAAkKeBwHEQAEAgAAAA==.',
Ba='Baane:BAAANQAECgQIBgABNQAECgUIHgATAHUQAA==.Babnik:BAEBNQAECn8eAAIFAAgK3A35rwCkAQAFAAgK3A35rwCkAQAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Balderdashe:BAAANQAECgEIAQAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAABNQAECn8+AAMTAAkK+xs+BQCvAQAKAAkKAhubRwAEAgATAAgKxhE+BQCvAQAAAA==.Belaim:BAAANQAECgEIAQAAAA==.Belovis:BAACNQAFFH8XAAISAAYK2xbLCABAAQASAAYK2xbLCABAAQA1AAQKfzkAAhIACgrlJJ4NADQDABIACgrlJJ4NADQDAAAA.Betsea:BAAANQADCgcIBwABNQAECgkJJwAUAOkUAA==.',
Bi='Bidock:BAAANQAECgUIBgAAAA==.Bidoof:BAABNQAECn8yAAIVAAoKvg7YJwC4AQAVAAoKvg7YJwC4AQAAAA==.Bigblunt:BAAANQADCgUIBgAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAABNQAECn8/AAIWAAkKqB7WBQBgAgAWAAkKqB7WBQBgAgAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAABNQAECn8cAAMUAAoK5Q6uaQBlAQAUAAgKngyuaQBlAQARAAYK8AduTwCpAAAAAA==.',
Bo='Boggrog:BAABNQAECn8eAAMXAAUKAhKwMABvAAAMAAUKSQ7r1QC0AAAXAAMKhROwMABvAAAAAA==.Bolz:BAAANQADCgYIBgAAAA==.Bonepicklucy:BAAANQADCgUIDgAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgUICgAAAA==.Bordeaux:BAAANQAECgMIBwABNQAECgYIGAALAOETAA==.Bosshog:BAABNQAECn81AAMYAAkKCwy+UwB2AQAYAAkKCwy+UwB2AQAEAAEKdgF+CQEXAAAAAA==.',
Br='Brabanzio:BAABNQAECn8iAAIKAAoKSxPAOgA8AgAKAAoKSxPAOgA8AgABNQAECgoKQgAEAJQfAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgMIBQAAAA==.Brotato:BAAANQABCgcICwABNQAECgcIDAAIAAAAAA==.Brotatochip:BAAANQAECgcIDAAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAABNQAECn8nAAIUAAoK8BsoFgD2AgAUAAoK8BsoFgD2AgAAAA==.Burningblunt:BAAANQAECgYIDAAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAABNQAECn8UAAIFAAcKSAfZzQD8AAAFAAcKSAfZzQD8AAABNQAECggIGQAZAMoFAA==.Castle:BAABNQAECn8fAAMUAAUKJQ/T5AC3AAAUAAQKYgrT5AC3AAASAAUKzAyLHwGmAAAAAA==.Catsinhats:BAAANQADCggIDQABNQAECgoKQAAPAHYcAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgoKQAAPAHYcAA==.',
Ce='Cecelya:BAABNQAECn8mAAMKAAoKZRlJPwBuAgAKAAoKZRlJPwBuAgALAAEKyAUoXwAzAAAAAA==.Celerian:BAAANQADCgUIBQAAAA==.',
Ch='Chablis:BAAANQAECgEIAwAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIIwAVADEdAA==.Chillpills:BAAANQABCgIIAgAAAA==.Chivactdl:BAAANQAECgIIAgABNQAECgoKSAAEAOgSAA==.Chosenn:BAAANQAECgUIDQAAAA==.Chotek:BAABNQAECn8eAAMHAAgKFBKOMABsAQAHAAgKFBKOMABsAQAJAAEKGwxsRAA0AAAAAA==.Chunknoriss:BAABNQAECn8bAAMaAAYKjxgEGABpAQAaAAYKjxgEGABpAQAbAAEKAACUdwAgAAABNQAECgoKSAAEAOgSAA==.',
Ci='Cilarnen:BAABNQAECn8fAAMUAAcKvBEJfwAlAQAUAAcKvBEJfwAlAQASAAYKYgZaIAGlAAAAAA==.',
Cl='Claudiuss:BAAANQAECggIDwABNQAECgoKQgAEAJQfAA==.Clure:BAABNQAECn8wAAIUAAoK4CIxFQArAwAUAAoK4CIxFQArAwABNQAECgoKQgAcAEcdAA==.Clurelock:BAAANQAECggIDQABNQAECgoKQgAcAEcdAA==.Clurethyr:BAABNQAECn9CAAIcAAoKRx2SBwDLAgAcAAoKRx2SBwDLAgAAAA==.',
Co='Conchobhar:BAAANQAECgYICQAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFH8OAAMKAAUKQg57EwBvAQAKAAUKQg57EwBvAQALAAEKAAByGABEAAA1AAQKfzcAAwoACgrkFts4AEQCAAoACQrOGNs4AEQCAAsACAq2HYshACoCAAAA.Corrosion:BAABNQAECn8qAAIdAAoKFx/+BgASAwAdAAoKFx/+BgASAwAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQADCgQIBAAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAABNQAECn8UAAISAAUKIxPB8QA5AQASAAUKIxPB8QA5AQABNQAFFAUICQASAK8UAA==.Crylessplz:BAAANQAECgUIDgABNQAECgoKPQARALoeAA==.',
Ct='Cthuwu:BAABNQAECn8aAAIeAAoKixNkOgAZAgAeAAoKixNkOgAZAgABNQAFFAUIDQAFAH8eAA==.',
Cv='Cvhamster:BAAANQAECgEIAQAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECn8rAAMJAAoKPBu+CwBvAgAJAAoKFRu+CwBvAgAfAAkK+BOrFQDOAQAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAABNQAECn8fAAIFAAkK1xOIgACeAQAFAAkK1xOIgACeAQAAAA==.Dados:BAAANQAECgUIBQAAAA==.Daeghun:BAAANQADCgYIBgAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQAECgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgYICQAAAA==.Darkkromdor:BAABNQAECn8tAAISAAoKXBu0YgByAgASAAoKXBu0YgByAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECn8qAAIVAAoKChfkJwBfAgAVAAoKChfkJwBfAgAAAA==.Deathcat:BAABNQAECn9AAAMPAAoKdhweLgB5AgAPAAoKdhweLgB5AgAQAAYKPgthYQAfAQAAAA==.Deathkiss:BAAANQAECgMJBQAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgQIBgAAAA==.Decayy:BAABNQAECn8mAAIOAAoKhhi2LQBeAgAOAAoKhhi2LQBeAgAAAA==.Dedbull:BAAANQAECgEIAgAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQAECgEIAgAAAA==.Des:BAAANQAECgEIAQAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAIAAAAAA==.',
Dk='Dkpheonix:BAABNQAECn89AAILAAoKJhQRFAAGAgALAAoKJhQRFAAGAgAAAA==.',
Do='Dolemite:BAABNQAECn8sAAMaAAkKFhDZEwCvAQAaAAkKFhDZEwCvAQAbAAYK3g8kNQDgAAAAAA==.Donalbain:BAABNQAECn9CAAIEAAoKlB/dCgBiAwAEAAoKlB/dCgBiAwAAAA==.Donninban:BAABNQAECn8YAAMYAAYKUhPShgCTAQAYAAYKUhPShgCTAQAEAAQKRxkTtACgAAAAAA==.Doodoobutter:BAAANQAECgIIAwABNQAFFAMIBgAgABoKAA==.',
Dr='Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAABNQAECn8bAAIhAAcKihZQCwB3AQAhAAcKihZQCwB3AQAAAA==.Drizzeh:BAAANQABCggIEAAAAA==.Drugoja:BAAANQADCgcICAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQAECgIIAgAAAA==.',
Ea='Eas:BAAANQADCgUIBQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQAECgUIDwAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elienda:BAAANQABCgIIAgAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eloweñ:BAAANQABCgQIBAAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECn8+AAIOAAoKBxZ8IgDXAQAOAAoKBxZ8IgDXAQAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAABNQAECn8hAAIHAAoK/gfbVgB7AQAHAAoK/gfbVgB7AQAAAA==.Emìly:BAABNQAECn9CAAMbAAkK3RXSGADUAQAbAAkK3RXSGADUAQAaAAgKFxYFHADEAQAAAA==.',
En='Entaria:BAAANQAECgUICQAAAA==.',
Ep='Ephria:BAABNQAECn8vAAMEAAoKiSQZEABDAwAEAAoKiSQZEABDAwAYAAEKAACXTQEnAAAAAA==.Episkey:BAAANQAECgQIDAAAAA==.',
Er='Eroversion:BAABNQAECn8kAAMGAAgK5RNsMQBKAQAGAAcKkBVsMQBKAQAfAAYKlwyEQgChAAABNQAECgoKZwAXAHEcAA==.Eroward:BAABNQAECn9nAAMXAAoKcRz0BwBTAgAXAAoKcRz0BwBTAgAMAAUK0wcO0wC6AAAAAA==.',
Es='Esmay:BAABNQAECn83AAIYAAkKaBAaWwBeAQAYAAkKaBAaWwBeAQAAAA==.',
Et='Ethren:BAABNQAECn9FAAIDAAkKExh9DAD3AQADAAkKExh9DAD3AQAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQADCgYIBQAAAA==.',
Ev='Evelynstar:BAAANQADCgMIAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.Fangsofblood:BAAANQAECgQIBAABNQAECgoKPgASAJ0QAA==.',
Fe='Felbolter:BAABNQAECn8qAAIZAAgKlR2rCAByAgAZAAgKlR2rCAByAgAAAA==.Feliri:BAAANQAECgIIAQAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQAECgEIAQAAAA==.Filgulfin:BAABNQAECn9IAAIFAAoK7BxSKQCNAgAFAAoK7BxSKQCNAgAAAA==.Finkate:BAAANQAECggIDAAAAA==.Firebringer:BAABNQAECn8uAAIiAAoKxQhXIQB/AQAiAAoKxQhXIQB/AQAAAA==.Fistmegently:BAAANQADCgYICwAAAA==.',
Fl='Flamehunter:BAABNQAECn8UAAIVAAgKjxW6MAB7AQAVAAgKjxW6MAB7AQAAAA==.Flo:BAABNQAECn9HAAQLAAoKMhQtIwAZAgALAAoKMhQtIwAZAgAKAAkKWgdYaACNAQATAAgKZw0wBgB5AQAAAA==.Floki:BAABNQAECn8XAAMXAAgKdRBkHQBsAQAXAAgKdRBkHQBsAQAMAAUKlAeG9wDuAAAAAA==.Flokin:BAAANQAECgIIAwAAAA==.Flowing:BAABNQAECn86AAQjAAoKgxIgCAAbAgAjAAoKgxIgCAAbAgAcAAYKIwcqMgAIAQAkAAQKfATALwCcAAAAAA==.',
Fo='Foods:BAABNQAECn9RAAQMAAoKghBdVwDlAQAMAAoKhQ9dVwDlAQAXAAUKWg2ELQDJAAAlAAIKUAtdLwBDAAAAAA==.',
Fr='Fripouille:BAAANQADCgQICAAAAA==.',
['Fæ']='Fæ:BAAANQAECgEIAQAAAA==.',
Ga='Gabmoo:BAAANQADCgMIAwAAAA==.Gaboo:BAABNQAECn8aAAISAAgKshH3ygCGAQASAAgKshH3ygCGAQAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAABNQAECn8uAAIFAAkKNBocSwAlAgAFAAkKNBocSwAlAgAAAA==.',
Gl='Glasgoww:BAAANQAECgEIAQABNQAECgoKQgAEAJQfAA==.Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQAECgQIBQAAAA==.',
Go='Goburina:BAABNQAECn8yAAIEAAoKVRIrXwDxAQAEAAoKVRIrXwDxAQAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gr='Gracee:BAAANQAECgEIAQAAAA==.Graedyn:BAAANQADCgEIAQAAAA==.Gryffen:BAAANQABCgcICQAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECn8oAAIFAAoKORuZTwCAAgAFAAoKORuZTwCAAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECn8zAAQjAAkK1A+jCQBlAQAjAAkKEw+jCQBlAQAkAAYKow3hHwBYAQAcAAUKzgRgOwC+AAAAAA==.Hallowed:BAAANQADCgUIBQAAAA==.Handofcope:BAAANQAECgYIEAAAAA==.Hartu:BAABNQAECn9MAAIXAAoKGBsFCQAyAgAXAAoKGBsFCQAyAgAAAA==.Harukasan:BAAANQADCgIIAgAAAA==.',
He='Healortank:BAAANQAECgEIAgAAAA==.Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgQIBgAAAA==.',
Hi='Hircine:BAAANQAECgEIAgAAAA==.',
Ho='Holysea:BAAANQAECgIIBAABNQAECgkJJwAUAOkUAA==.Honk:BAAANQAECgQIBAAAAA==.',
Ic='Ichiko:BAAANQADCgUIBQAAAA==.',
Im='Imwithfloki:BAABNQAECn8dAAQfAAcKzBfaHgCoAQAfAAcKzBfaHgCoAQAJAAEKAAC1OwBLAAAGAAEKhhDBcgAuAAAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUICAAAAA==.Isamidor:BAABNQAECn8mAAIFAAkK6SW2CACXAwAFAAkK6SW2CACXAwAAAA==.Ismokeu:BAABNQAECn8sAAMKAAoKKRnCSABMAgAKAAoKKRnCSABMAgALAAEKAAC0cQAAAAAAAA==.Ismyn:BAAANQAECgMIBAAAAA==.Istran:BAAANQAECggIEgAAAA==.',
Iv='Ivrys:BAAANQAECgcIEAAAAA==.',
Iw='Iwillbethere:BAAANQAECgIIBQAAAA==.',
Ja='Jackoneal:BAABNQAECn8sAAMSAAoKmASV1wAVAQASAAoKmASV1wAVAQARAAEKAABnfwAdAAAAAA==.Jalidelo:BAABNQAECn8nAAIKAAoKchI6WgATAgAKAAoKchI6WgATAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECn87AAIeAAoKlxySIQB/AgAeAAoKlxySIQB/AgAAAA==.Jokersfists:BAABNQAECn8lAAIiAAoKlBWREQAzAgAiAAoKlBWREQAzAgABNQAECgoKKQANAG8OAA==.Jokersmage:BAABNQAECn8pAAINAAoKbw5dXgDrAQANAAoKbw5dXgDrAQAAAA==.Joraflheim:BAAANQAECgEIBAAAAA==.Joranbragi:BAABNQAECn8oAAISAAYKcwP9LAGUAAASAAYKcwP9LAGUAAAAAA==.Jordanjr:BAABNQAECn9FAAMmAAoKrBfOEQATAgAFAAoKOBL3TACHAgAmAAoK5BPOEQATAgAAAA==.Josunlee:BAAANQAECggIDgAAAA==.Jotoonice:BAABNQAECn8oAAMWAAoKuBGtFgBIAQAWAAYKlxStFgBIAQANAAgKOgeoRwEWAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFH8NAAMmAAYK+w0jEwAOAQAmAAQKtw4jEwAOAQAFAAMKfwuPGwCpAAA1AAQKfzgAAyYACgpzHXccAG8CACYACgp+FXccAG8CAAUABArvIW68AB4BAAAA.',
Ju='Juicyfruit:BAAANQABCgYICQAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAABNQAECn9FAAIFAAkKWRRRWwD7AQAFAAkKWRRRWwD7AQAAAA==.Kaedina:BAABNQAECn8fAAMKAAoKrwuxbADYAQAKAAoKrwuxbADYAQALAAcKhg0UKwAUAQABNQAECgoKRQAmAKwXAA==.Kallista:BAAANQADCgYIDwAAAA==.Karugan:BAAANQADCgIIAgABNQADCgcICgAIAAAAAA==.Karvel:BAABNQAECn8jAAIOAAoKeBmXLwBUAgAOAAoKeBmXLwBUAgAAAA==.Katally:BAAANQAECgEIAQAAAA==.Kaychow:BAAANQAECgQICgABNQAECgoKMwAUAGsfAA==.Kaydullz:BAABNQAECn8jAAIKAAoKEBg0LgB4AgAKAAoKEBg0LgB4AgAAAA==.',
Kc='Kchowchow:BAAANQAECgUICAABNQAECgoKMwAUAGsfAA==.',
Ke='Kelonaar:BAACNQAFFH8WAAMYAAQKaxfgDgDnAAAYAAQKaxfgDgDnAAAEAAMK5gPWJgBuAAA1AAQKfysAAxgACgpfIGojAPkCABgACgpfIGojAPkCAAQAAwq7GPLiAKQAAAAA.Keloni:BAAANQAECgUIBgABNQAFFAQIFgAYAGsXAA==.Kenack:BAAANQAECgQIDAAAAA==.',
Kh='Kharys:BAAANQADCggIHAAAAA==.Khell:BAAANQADCgUIBQAAAA==.',
Ki='Killallnius:BAAANQADCgIIAgAAAA==.Killermoomoo:BAAANQAECgQIBgAAAA==.',
Kl='Kloverr:BAAANQAECgYIEQAAAA==.Klub:BAAANQAECgEIAQAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUICQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBwAAAA==.Krooler:BAAANQAECgMJBQAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Ladgarkk:BAABNQAECn8hAAMUAAoKcBlcGADkAgAUAAoKcBlcGADkAgASAAEKDAfgiQE0AAAAAA==.Lanval:BAABNQAECn9NAAISAAoKbho/SgA8AgASAAoKbho/SgA8AgAAAA==.Latinlover:BAAANQAECgIIAwAAAA==.Laurian:BAAANQAECgEIAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECn9PAAIfAAoKsB31CACjAgAfAAoKsB31CACjAgAAAA==.Leftblank:BAAANQAECgQIBQAAAA==.',
Li='Lich:BAAANQAECgQIBQAAAA==.Lighthugger:BAABNQAECn84AAISAAoKgxqOXAAKAgASAAoKgxqOXAAKAgAAAA==.Lilyoptra:BAABNQAECn8fAAIeAAcKDQN0yQCsAAAeAAcKDQN0yQCsAAABNQAECgcIHwAUALwRAA==.Liqmycrits:BAAANQADCggIGwAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECggIIwAVAKAQAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwAIAAAAAA==.',
Lo='Lockpockets:BAABNQAECn8cAAIeAAcKLwoBowD8AAAeAAcKLwoBowD8AAAAAA==.Loriane:BAAANQAECgIIAgABNQAECggIFAAEAGkjAA==.Lorianth:BAABNQAECn84AAImAAoK6g9kGgCdAQAmAAoK6g9kGgCdAQAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.Loveisbeauty:BAAANQADCgcIBQAAAA==.',
Lu='Lucifér:BAAANQABCggICgAAAA==.Lundigras:BAAANQADCgUIBQAAAA==.',
Ly='Lychi:BAAANQAECgQIBgAAAA==.Lylora:BAABNQAECn9VAAIGAAoKiSZmAABSBAAGAAoKiSZmAABSBAAAAA==.',
['Lê']='Lêmonaide:BAABNQAECn8qAAMKAAoKUxX1UgAqAgAKAAoKUxX1UgAqAgALAAUKIQU8RwB6AAAAAA==.',
['Lô']='Lôki:BAAANQAECgUIBQAAAA==.',
Ma='Madclaws:BAABNQAECn9QAAMfAAoKGR+ICwBxAgAfAAoKrRuICwBxAgAHAAkKNB8VFQBfAgAAAA==.Madman:BAABNQAECn8XAAIaAAYKRQyYIgDkAAAaAAYKRQyYIgDkAAAAAA==.Magekaestey:BAAANQADCggIDwABNQAECgoKLAAMAJcMAA==.Malala:BAAANQADCgYIEwABNQAECgoKWAAKAIwfAA==.Malyndra:BAAANQAECgYIDgABNQAECgcIEAAIAAAAAA==.Mantre:BAAANQAECgEIAQAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECn8kAAIeAAoKwQeYnQCcAQAeAAoKwQeYnQCcAQAAAA==.Masy:BAAANQAECggIDwAAAA==.',
Me='Mesmash:BAABNQAECn8zAAIXAAgKwyHOCQCrAgAXAAgKwyHOCQCrAgAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDgABNQAECgYIDwAIAAAAAA==.Metatotem:BAAANQAECgYICAABNQAECgYIDwAIAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIBQAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQAECggIEAABNQAECgkJLwAKACwbAA==.Miniborg:BAAANQAECgUIDQABNQAFFAUICQASAK8UAA==.Minidude:BAABNQAECn8fAAIMAAoKfhS+PQA8AgAMAAoKfhS+PQA8AgAAAA==.Misfire:BAAANQAECgEIAQAAAA==.Mistycrusade:BAAANQAECgUIDQAAAA==.Mizzen:BAABNQAECn83AAMPAAoKJR93CwCyAgAPAAoKJR93CwCyAgAOAAIKpQzytABfAAABNQAFFAUIDgALANcRAA==.',
Mo='Moejojojo:BAABNQAECn8ZAAIbAAgKHR7pHgA5AgAbAAgKHR7pHgA5AgAAAA==.Moofasaha:BAABNQAECn8cAAQEAAcKXx63YgDlAQAEAAcKXx63YgDlAQAYAAQKggjS+wCbAAAdAAEKSggKMwA9AAAAAA==.Morog:BAABNQAECn8UAAMFAAgKHB8rOwC4AgAFAAgKHB8rOwC4AgAmAAEKAACNigA0AAAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAABNQAECn8YAAINAAgKTAjPMAE7AQANAAgKTAjPMAE7AQAAAA==.',
['Mâ']='Mârshy:BAAANQAECgUIBgABNQAFFAEIAQAIAAAAAA==.',
['Mã']='Mãrshy:BAABNQAECn8cAAIKAAgKgB6IOgB/AgAKAAgKgB6IOgB/AgABNQAFFAEIAQAIAAAAAA==.',
['Mä']='Märshy:BAAANQAECgQIBwABNQAFFAEIAQAIAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICgAAAA==.Nanarus:BAABNQAECn9YAAMKAAoKjB+0DABsAwAKAAoKjB+0DABsAwALAAIKwAXHUgBOAAAAAA==.Nashalie:BAABNQAECn87AAMeAAoKbCGjGAAlAwAeAAoKbCGjGAAlAwAZAAIKOgzdVQB9AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAABNQAECn8YAAIEAAkKqBlGWwCRAQAEAAkKqBlGWwCRAQAAAA==.Neverfrozen:BAAANQAECgYICgAAAA==.Nexbasia:BAABNQAECn89AAIJAAoKtxFgDwCxAQAJAAoKtxFgDwCxAQAAAA==.',
Ni='Nickyboy:BAAANQAECgUIBQAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIBAAAAA==.Nomad:BAAANQADCggIGgAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Ny='Nymmycup:BAAANQAECgMIBgAAAA==.',
Oc='Octt:BAAANQAECgYIDAAAAA==.',
Ol='Oldcannabis:BAABNQAECn8dAAIFAAgKyQotmQDVAQAFAAgKyQotmQDVAQAAAA==.',
Om='Ominis:BAAANQADCgQIBAAAAA==.',
Oo='Oomaw:BAAANQAECgEIAQAAAA==.',
Or='Ormbar:BAAANQADCgIIAgAAAA==.Ornimus:BAABNQAECn8kAAQRAAUKkhUGQAD6AAARAAUKkhUGQAD6AAASAAQKbQGShQFSAAAUAAIKuwFuHgE4AAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAACNQAFFH8HAAILAAQKdBpcCgBTAQALAAQKdBpcCgBTAQA1AAQKfxwAAgsACQpNIisRAOgCAAsACQpNIisRAOgCAAAA.',
Oz='Ozo:BAAANQAECgQIDgAAAA==.',
Pa='Paiva:BAAANQAECgMIAwAAAA==.Palandor:BAAANQAECgEIAQAAAA==.Pallydoof:BAAANQADCggICQAAAA==.Pallyscorned:BAABNQAECn8vAAIRAAoKmxf1EgDlAQARAAoKmxf1EgDlAQAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECggIEgAIAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Pandaria:BAAANQAFFAEIAQAAAA==.Panduh:BAABNQAECn8xAAMbAAkKZiEPCwAjAwAbAAkKECEPCwAjAwAgAAcKjx+bDgAKAgAAAA==.',
Ph='Phenixy:BAAANQAECgQIBgAAAA==.Phoebell:BAABNQAECn8XAAIGAAcKyQilQQDoAAAGAAcKyQilQQDoAAAAAA==.Phoinix:BAAANQADCgcIDgAAAA==.',
Pi='Pinkducky:BAAANQADCggIHgAAAA==.',
Pl='Plen:BAAANQAECgIIAwABNQAECgkJLwAKACwbAA==.',
Po='Ponyo:BAABNQAECn9CAAIKAAoKBSQrBgDCAwAKAAoKBSQrBgDCAwAAAA==.Poppyseed:BAAANQAECgcIBwAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pr='Prinnce:BAAANQAECgYIEAABNQAECgkJQgAbAN0VAA==.',
Pu='Pulmifinger:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECn8cAAMmAAgKXg92OACMAQAmAAgKnQ52OACMAQAFAAMK1hF5HgHAAAAAAA==.',
Ra='Raddra:BAAANQAECgUICwAAAA==.Raddrah:BAAANQAECgMIBQAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Raddraw:BAAANQADCgEIAQAAAA==.Radmuster:BAAANQAECgIIAgABNQAECgoKHgALAG0SAA==.Radra:BAABNQAECn81AAIiAAoKNxAwIACLAQAiAAoKNxAwIACLAQAAAA==.Raeku:BAABNQAECn8vAAInAAoKVx8gAgCyAgAnAAoKVx8gAgCyAgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBwAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECn88AAIKAAoKHh/ZDQBhAwAKAAoKHh/ZDQBhAwAAAA==.Redhaven:BAABNQAECn8eAAIKAAoKeA0jUQDfAQAKAAoKeA0jUQDfAQAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAABNQAECn8+AAISAAoKnRArcgDXAQASAAoKnRArcgDXAQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rokz:BAAANQAECgIIAgAAAA==.Rolas:BAAANQAECgEIAgAAAA==.Ronfax:BAACNQAFFH8RAAIEAAYKGRZcCADKAQAEAAYKGRZcCADKAQA1AAQKfzsAAgQACgrgIFoSADUDAAQACgrgIFoSADUDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgYIDQAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgYIDwAIAAAAAA==.',
Ru='Ruby:BAABNQAECn8cAAIgAAkKBiDbBQD4AgAgAAkKBiDbBQD4AgAAAA==.Rul:BAAANQADCgIIAgABNQAECgkJMQAbAGYhAA==.',
Ry='Ryllae:BAAANQAECgEIAQABNQAECggIIwAVADEdAA==.Ryuu:BAAANQAECgIIBgAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rå']='Råhl:BAAANQABCgcICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECn8dAAMhAAoKXwgIGgC2AAAeAAoK/AfaqwB7AQAhAAQKuwYIGgC2AAABNQAECgoKKAAFADkbAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECgoKKAAFADkbAA==.',
Sa='Saint:BAABNQAECn8tAAMSAAgKJRMcwACcAQASAAcKWRYcwACcAQAUAAgKrRRCjwBwAQAAAA==.Sallypally:BAAANQABCgQIBgAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Saltsquirrel:BAAANQABCgIIAgAAAA==.Sarandria:BAAANQAECgQIBAABNQAECgkJGQAWAKQYAA==.Sarinae:BAABNQAECn8sAAQjAAoK8AaxEAAsAQAjAAoKsgaxEAAsAQAkAAYKPgVZKgDVAAAcAAEK3QFCPwASAAAAAA==.Sarmuc:BAABNQAECn9DAAIdAAoKgRiECQDdAgAdAAoKgRiECQDdAgAAAA==.Saryda:BAABNQAECn8YAAMLAAYK4ROHNQB3AQALAAYK4ROHNQB3AQAKAAEK1wKJ8gArAAAAAA==.Sauda:BAAANQAECgUIDgAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAgAAAA==.Scubagal:BAABNQAECn8XAAISAAcKXAM/JwGcAAASAAcKXAM/JwGcAAAAAA==.Scythraza:BAAANQAECgcICwAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Sellenah:BAAANQADCgUIBAABNQAECgUICgAIAAAAAA==.Selûne:BAAANQABCggICgAAAA==.Sensu:BAABNQAECn8eAAMTAAUKdRAHCQANAQATAAUKdRAHCQANAQALAAEKbANCYwAqAAAAAA==.Serrest:BAAANQAECgYICgAAAA==.Seä:BAABNQAECn8nAAIUAAkK6RQZVQAaAgAUAAkK6RQZVQAaAgAAAA==.',
Sh='Shacktown:BAAANQAECggIBQAAAA==.Shadowdoh:BAAANQAECgcIEAAAAA==.Shapzan:BAABNQAECn8ZAAMHAAYKWQ1lVAC7AAAHAAYKrgplVAC7AAAfAAMKnhBNRgCZAAAAAA==.Sharks:BAAANQAECgQJCAAAAA==.Shivant:BAABNQAECn9IAAIEAAoK6BLERADpAQAEAAoK6BLERADpAQAAAA==.',
Si='Sidebürns:BAAANQAECgQIBAAAAA==.Silendreas:BAAANQAECgEIAQAAAA==.',
Sl='Sloth:BAABNQAECn8+AAIOAAoKaiLUCAD3AgAOAAoKaiLUCAD3AgAAAA==.',
Sm='Smalltwngirl:BAABNQAECn8aAAIGAAgKBRHKKgB8AQAGAAgKBRHKKgB8AQABNQAFFAYIEQAEABkWAA==.',
So='Solaire:BAAANQAECgQICAAAAA==.Solaspirus:BAABNQAECn8XAAQVAAgKAxLYUQBOAQAVAAYK8xPYUQBOAQAiAAMKuwhXRwBpAAAoAAEKLRD4NAAoAAAAAA==.Solinius:BAAANQADCggIGgAAAA==.Songbreeze:BAABNQAECn8vAAMKAAkKLBsUKgDBAgAKAAkKLBsUKgDBAgALAAUKmQUkUADRAAAAAA==.Sonofagun:BAAANQAECgYICQAAAA==.',
Sp='Spectors:BAABNQAECn8zAAQhAAoKsAchDQBQAQAhAAoKUQchDQBQAQAeAAcKHwPs5wD5AAAZAAEKAAA5hQAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgYIEQAAAA==.Strykah:BAAANQAECgEIAQAAAA==.Stumpypete:BAAANQAECgEIAwAAAA==.',
Su='Sugarcube:BAAANQAECgEIAQAAAA==.Sugarmarks:BAAANQAECgMIBQAAAA==.',
Sw='Sweetstorm:BAABNQAECn8vAAIVAAoK+QPlSgDlAAAVAAoK+QPlSgDlAAAAAA==.',
Sy='Sydburns:BAAANQABCgYICAABNQAECgQIBAAIAAAAAA==.Sydley:BAAANQABCgUIBQAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAABNQAECn8hAAMYAAgKBAbnagAvAQAYAAgKBAbnagAvAQAEAAgK0QLvjgD0AAAAAA==.Tarixx:BAABNQAECn8VAAMSAAgKlB1BcQDZAQASAAgKKBpBcQDZAQARAAYKVyB1JQC0AQAAAA==.Tazanoth:BAABNQAECn82AAQFAAoKBBwdYgBSAgAFAAoKwxodYgBSAgAnAAgK6BskBgBDAgAmAAYKPQo+RwAiAQAAAA==.',
Te='Tekeela:BAABNQAECn8qAAIFAAoKZSCsGwDHAgAFAAoKZSCsGwDHAgABNQAFFAUIDQAFAH8eAA==.Tekeelà:BAACNQAFFH8NAAIFAAUKfx7WDwD7AAAFAAUKfx7WDwD7AAA1AAQKfz8AAgUACgqTItgOAGsDAAUACgqTItgOAGsDAAAA.Terzo:BAAANQABCgQIBgAAAA==.',
Th='Thalarus:BAAANQADCgMIBgABNQADCgcICgAIAAAAAA==.Thalion:BAAANQAECgYICgAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Theroux:BAAANQAECgEIAQAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAABNQAECn8ZAAMUAAkKjgxAeAA5AQAUAAkKjgxAeAA5AQASAAEKewYquwEqAAAAAA==.Thobu:BAAANQAECgUIBgAAAA==.Thornscale:BAABNQAECn8jAAQjAAoKeAl3DgBfAQAkAAkK+weoHQB0AQAjAAgKEwl3DgBfAQAcAAEKJQIMUwAmAAAAAA==.',
Ti='Tielee:BAAANQAECgUIBQAAAA==.Tigolcrittys:BAAANQADCggIEQABNQAECgoKKAAFADkbAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAABNQAECn8WAAIEAAkK+hiMOgAXAgAEAAkK+hiMOgAXAgAAAA==.Totem:BAAANQAECgUICwAAAA==.Tovê:BAABNQAECn8fAAMEAAoK3BR2KwBjAgAEAAoK3BR2KwBjAgAYAAUKAwuaxwADAQAAAA==.',
Tr='Traumajazz:BAAANQAECgEIAQAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECn8dAAMZAAgKzCCABADhAgAZAAgKzCCABADhAgAhAAMKQBLkGQC3AAAAAA==.Trxcy:BAAANQAECgMIBQAAAA==.',
Tu='Turger:BAAANQAECgEIAgABNQAECgcIHAAEAF8eAA==.',
Um='Umbrafang:BAAANQAECgEIAQAAAA==.',
Va='Vaeluptuous:BAABNQAECn8hAAIeAAcK5BCeigAzAQAeAAcK5BCeigAzAQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECn8rAAMZAAoKwSC2BADaAgAZAAgKSh62BADaAgAeAAkKbBvlYQAzAgAAAA==.Valdreu:BAAANQADCgUIBQAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAABNQAECn8XAAIDAAkKzQvFJAADAQADAAkKzQvFJAADAQAAAA==.Varaine:BAAANQAECgUIBQABNQAECggIIwAVAKAQAA==.',
Ve='Veebs:BAAANQAECgYIBwAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECn9FAAIiAAoK3xWaEwAWAgAiAAoK3xWaEwAWAgAAAA==.Vizon:BAAANQADCggIGAAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIGwAAAA==.',
Vy='Vynesta:BAABNQAECn8jAAIVAAgKMR2PIQCPAgAVAAgKMR2PIQCPAgAAAA==.',
Wa='Wanagi:BAABNQAECn8ZAAISAAUKJgTARAF3AAASAAUKJgTARAF3AAAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECn8sAAIMAAoKlwzbcACaAQAMAAoKlwzbcACaAQAAAA==.Warriorguyes:BAABNQAECn8jAAIMAAkKXh2ySwAKAgAMAAkKXh2ySwAKAgAAAA==.',
We='Weewillywnky:BAAANQAECgEIAQAAAA==.',
Wh='Whomper:BAAANQAECgQICgAAAA==.',
Wi='Wickedshadow:BAAANQADCgIIAgAAAA==.Widowx:BAABNQAECn8cAAIYAAkKgAxJdAAXAQAYAAkKgAxJdAAXAQAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECn9DAAIOAAkK+RE7LACWAQAOAAkK+RE7LACWAQAAAA==.',
Wo='Womphunt:BAABNQAECn8wAAIFAAoK0BmoNQBiAgAFAAoK0BmoNQBiAgAAAA==.',
Wu='Wulyn:BAABNQAECn8WAAIaAAUKBALaMQBmAAAaAAUKBALaMQBmAAAAAA==.',
Wy='Wylla:BAABNQAECn8fAAIbAAYKQwyRRAD2AAAbAAYKQwyRRAD2AAAAAA==.',
Xa='Xalethra:BAAANQAECgQIBwAAAA==.',
Xe='Xenophobias:BAABNQAECn8hAAIOAAoKiAwtLgCLAQAOAAoKiAwtLgCLAQAAAA==.',
Xs='Xsuns:BAABNQAECn83AAIGAAkK2hdlIgATAgAGAAkK2hdlIgATAgAAAA==.',
Yv='Yve:BAAANQAECgMICAAAAA==.',
Za='Zabberz:BAAANQAECgMIBQAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAABNQAECn8cAAIdAAgKLAi4HAA1AQAdAAgKLAi4HAA1AQAAAA==.Zarathiel:BAABNQAECn8fAAIMAAoKew1EnwDOAQAMAAoKew1EnwDOAQAAAA==.',
Ze='Zeddicus:BAABNQAECn83AAMhAAkK8wbcDQBDAQAhAAkK8wbcDQBDAQAeAAYKnwMLwQC8AAAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggIDAAAAA==.',
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
